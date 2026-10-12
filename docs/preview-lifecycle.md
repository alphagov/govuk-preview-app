# The preview lifecycle

## Building a preview

Creating a `Preview` (an app name + branch) enqueues `PreviewsCreateJob`,
which delegates to `PreviewBuilder#build!`. This drives the preview
through `queued` → `waiting_for_image` → `starting` → `running`, or
`failed` at any step - a failed build can be retried, carrying on from
wherever it stopped rather than starting over:

1. **Dependencies first.** For each app named in the manifest's
   `dependencies`, in order, build a fresh, dedicated `Preview` (always
   branch `main`, never shared across parents) recursively, and inject
   its `PLEK_SERVICE_<NAME>_URI` (`http://<its Service name>`) into the
   parent's env once it's running. Order matters: each dependency also
   inherits the resolved `PLEK_SERVICE_*_URI`s of every dependency built
   *before* it in the same list - e.g. Whitehall's `frontend` dependency,
   declared after `publishing-api`, ends up pointed at the preview's own
   Content Store, not Frontend's default of the real GOV.UK one.
2. **Resolve the image** - see [Image resolution](#image-resolution).
3. **Config overrides** (`ConfigOverrides`) - a fixed initializer,
   mounted into every pod from a ConfigMap, fixing problems a plain env
   var can't reach: some apps hardcode an `x_sendfile_header`, some
   apps' `database.yml` ignores `DATABASE_URL` in production, and some
   set `config.hosts` to a real GOV.UK-only allowlist that would 403
   every preview hostname. It's rendered once, at creation - a change to
   it never reaches an already-running preview, see
   [Troubleshooting](troubleshooting.md).
4. **Database**, if the manifest declares one (`KubernetesDatabaseRunner`)
   - a dedicated, never-shared MySQL, Postgres or MongoDB StatefulSet
   with its own small volume, then a `db:create db:schema:load` Job (or,
   for Mongoid apps, `db:mongoid:create_indexes`) and a `db:seed` Job.
5. **Setup tasks**, if the manifest declares any - each named `bin/rails`
   task, in order, as its own Job (e.g. the taxonomy Whitehall needs in
   Publishing API before a document can be tagged).
6. **Start** (`KubernetesRunner#start!`) - a Deployment and a Service,
   waiting until the app is actually serving. If the manifest declares a
   `worker_command`, a second Deployment runs that from the same image
   (e.g. Publishing API's Sidekiq worker, which pushes published content
   to Content Store).

Every object is named by `ContainerName` (the preview's slug, truncated
and hashed to fit Kubernetes' 63-character name limit) and labelled with
the preview's id.

## Image resolution

Nothing is built in the cluster. `ImageResolver` finds the image GOV.UK's
own GitHub Actions already pushed to `ghcr.io/alphagov/govuk/<repo>`:

- **`main`** - the app's latest release, tagged e.g. `v1234` by its own
  deploy workflow. Every dependency preview runs `main`, so these work
  out of the box.
- **any other branch** - the image tagged with the branch's head commit
  SHA, pushed by the app's "Build image from PR" workflow (with pushing
  enabled). A preview waits (`waiting_for_image`) until it appears, so
  you can create one straight after pushing.
- **`local:<tag>`** - local development only, built from your own
  checkout and loaded straight into the kind cluster - see
  [Local development](local-development.md#previewing-local-code).

On integration, images are pulled through GOV.UK's ECR pull-through
cache in front of GHCR (`PREVIEW_APP_IMAGE_REGISTRY`).

## Core and full stacks

By default a preview runs its **core stack**: the app and only the
`dependencies` it needs to work - e.g. Whitehall and Publishing API (with
its worker and database). Publishing API is never left out of Whitehall's
core stack: what a Whitehall preview is usually *for* is Whitehall's own
interaction with it (e.g. how it handles Publishing API's validation
errors), so it has to be the real thing. Content Store is downstream of
Publishing API, so largely irrelevant to Whitehall itself in a core
stack.

For apps that declare `full_stack_dependencies`, a **full stack**
additionally runs those too - apps needed only to see the previewed
app's output end to end (e.g. Frontends, to view a published page;
Content Stores, to view what Publishing API pushed), never apps it
directly interacts with. For Whitehall, that's both Content Stores (via
Publishing API) and both Frontends, for roughly twice the memory. Each
app's full stack is its own - a future Collections Publisher's would be
its Collections apps plus Publishing API's Content Stores, no Frontend.
On the new preview form, choosing an app with a full stack reveals a
"Full stack" checkbox listing what it adds.

In a core stack, an app that would have used a left-out
`full_stack_dependencies` entry is pointed at [the sink](architecture.md#the-sink)
instead.

An app whose full stack includes its own Frontends can link to them too:
Whitehall's "View on website"/"Preview on website" links (and every
other public link it builds) point at its preview's Frontend and draft
Frontend in a full stack, via `env_aliases` setting `GOVUK_WEBSITE_ROOT`
and `PLEK_SERVICE_DRAFT_ORIGIN_URI`, and at the real integration site
otherwise. Every preview runs with `GOVUK_ENVIRONMENT=integration`,
which is how apps should tell which environment they're in.

Whitehall's full stack also runs its own Asset Manager, so uploads (e.g.
a news story's lead image) can be seen on its Frontends - see
[trust and design trade-offs](trust-and-design-tradeoffs.md#asset-managers-own-gate)
for why Asset Manager's own Signon gate is skipped. Whitehall and Asset
Manager each run their worker as a second container in their web pod,
sharing a directory with it (`shared_volumes`).

A running preview can be switched between the two stacks from the
previews page (`PreviewResizer`). Nothing already running is rebuilt or
loses data: the extra apps are added (or removed), and anything whose
dependency addresses change is restarted with the new ones
(`PreviewBuilder#reconfigure!`). Adding the full stack also re-runs the
manifest's `resync_tasks` (e.g. Publishing API re-sending everything it
holds to the new Content Stores).

## Sleeping and waking

Every preview stack has to fit in the `previews` namespace's
`ResourceQuota` - on integration that's the cost cap (the cluster
autoscaler adds nodes for anything within it), and locally it's set to
what the single kind node can hold. Before a stack is built or woken,
`PreviewCapacity` works out how much memory it needs and, if there isn't
room, puts the least recently used *other* stacks to sleep until there
is. A stack used in the last 15 minutes is never put to sleep; if that
leaves no room, the preview says it's at capacity rather than waiting
indefinitely.

Sleeping (`PreviewSleeper`) scales every Deployment and database in a
stack to zero, keeping everything else - Services, config, images, and
database volumes - so waking it is just scaling back up: no image pulls,
migrations or seeds, and everything published into it is still there.
Visiting a sleeping preview (or one of its dependencies' public
hostnames) shows a self-refreshing "Waking up" page and wakes the whole
stack; previews can also be put to sleep or woken from the previews
page.

"Least recently used" means least recently *interacted with*: each
preview records when someone last created, visited, retried, woke, put
to sleep or resized it (`Preview#record_interaction!`) - never anything
automatic, like a build finishing or a preview being put to sleep to
make room for something else. The previews page lists previews by the
same thing, most recent first.

## Tearing down

Deleting a preview enqueues `PreviewsDestroyJob`, which delegates to
`PreviewDestroyer#destroy!` - recursively deleting every dependent
preview's Kubernetes objects (and database volume) first, then the
preview's own.

## Staying honest about what's actually running

`PreviewReconciler` runs at boot and marks any `running` or `sleeping`
preview `failed` if its Deployment or database no longer exists - e.g.
after the local kind cluster was recreated, or its manifest entry was
removed. A pod that merely crashed or was rescheduled doesn't count -
Kubernetes recreates it by itself.

`InterruptedJobResumer` also runs at boot, in the worker only, and
re-queues the build, wake or teardown of any preview whose Sidekiq job
was lost part-way - e.g. because Docker Desktop was quit mid-build.
Every one of those jobs is safe to re-run from any point.
