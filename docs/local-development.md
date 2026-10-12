# Local development

## Prerequisites

- Docker Desktop (or another Docker engine), with ~6GB of memory to
  spare for a full Whitehall preview.
- [kind](https://kind.sigs.k8s.io/) and kubectl: `brew install kind
  kubectl`.
- `*.dev.gov.uk` resolving to `127.0.0.1` - the standard GOV.UK dev
  machine setup. If `curl -sI
  http://frontend-main.govuk-preview-app.dev.gov.uk` fails to resolve,
  add a wildcard rule for the whole domain to your dnsmasq config (e.g.
  `/opt/homebrew/etc/dnsmasq.d/`):

  ```
  address=/dev.gov.uk/127.0.0.1
  ```

## Getting started

```
bin/kind-up
```

This creates a single-node kind cluster called `govuk-preview-app`,
builds Preview App's image, loads it into the cluster, and applies
`kubernetes/local` - the same `previews` namespace objects integration
uses (`kubernetes/previews`), plus Preview App itself and its own
Postgres and Redis in the `apps` namespace, mirroring integration's
layout.

Visit <http://govuk-preview-app.dev.gov.uk:8080/previews>. Once a
preview reaches "running", it's reachable at its own hostname, e.g.
<http://whitehall-main.govuk-preview-app.dev.gov.uk:8080/>.

Preview App listens on `127.0.0.1:8080` rather than port 80 because
govuk-docker's own nginx-proxy already holds port 80 on most GOV.UK dev
machines, and only one process can bind a given host port - this way
both run side by side. On integration there's no port in any URL.

The local quota (`kubernetes/local/kustomization.yaml`) holds one full
Whitehall stack, plus a build and other small previews, at a time -
anything else is put to sleep to make room, as on integration. Giving
Docker Desktop more memory and raising that quota to match lets more
stay awake.

After changing Preview App's own code, run `bin/kind-deploy` to rebuild
and redeploy it (existing previews keep running - though see
[Troubleshooting](troubleshooting.md#a-code-change-isnt-taking-effect-on-an-existing-preview)
if the change was to something baked into a preview pod at creation
time). `bin/kind-down` deletes the cluster, every preview, and Preview
App's own database.

To see how much memory each preview stack actually uses, next to what
its pods request and their limits, run `bin/preview-usage` (it uses
metrics-server, which `bin/kind-up` installs locally).

Every `kubectl` command in these scripts passes `--context
kind-govuk-preview-app`, so they can never touch any other cluster. To
look around yourself:

```
kubectl --context kind-govuk-preview-app -n previews get pods
```

## Previewing a branch

Any branch whose image has been pushed to GHCR can be previewed
locally, exactly as on integration - Preview App never needs the code
itself. `main` (and so every dependency) works straight away; other
branches need the app's "Build image from PR" workflow to have pushed
their image first.

## Previewing local code

Code that's never been pushed - including uncommitted changes - can be
previewed too:

```
bin/preview-build frontend            # builds ~/govuk/frontend; or pass a path
```

This builds your checkout's own Dockerfile with your local Docker,
loads the image straight into the kind cluster (no registry involved),
and prints a branch value like `local:my-branch-ab12cd3` (with
`-dirty-<timestamp>` if there were uncommitted changes, so each state of
your checkout gets its own image). Use that value as the branch when
creating a preview of that app. Its dependencies still run `main`, as
for any other preview.

`bin/preview-build` takes any app in `config/govuk_apps.yml`; apps
sharing a repo share an image, so one Frontend build can be previewed as
either `frontend` or `draft-frontend`. Re-run it after further changes,
and create a new preview with the new value - an existing preview never
changes underneath you.

`local:` images only exist in local development
(`PREVIEW_APP_LOCAL_IMAGES`); integration rejects them. Only the tag is
ever user-supplied - the image is always `govuk-preview-local/<repo>` -
so a `local:` value can't point at an arbitrary image. If a preview
names a tag that hasn't been loaded, it fails straight away saying so.

## Running the tests

The specs need Postgres and Redis, like any GOV.UK Rails app - e.g. via
govuk-docker, or:

```
docker run -d --rm --name preview-app-test-postgres -p 55432:5432 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17
export RAILS_ENV=test TEST_DATABASE_URL=postgres://postgres@127.0.0.1:55432/govuk_preview_app_test
bin/rails db:setup
bin/rails dartsass:build
bundle exec rspec
```

Kubernetes, GitHub and GHCR are all stubbed with WebMock in these specs
- they never need a cluster. That also means they can't catch a real
networking/routing regression - see the next section.

## Smoke-testing against a real cluster

`bin/smoke-test` builds (or reuses) real previews in your local kind
cluster and checks the two things no spec can: a real HTTP round trip
through `HostRouter`'s Signon gate, and (with `--full`) a real
pod-to-pod request into Asset Manager's own `MediaController`. Run it
after `bin/kind-up`/`bin/kind-deploy`:

```
bin/smoke-test         # routing + Signon round trip only
bin/smoke-test --full  # also the slower Asset Manager check
```

It doesn't delete anything it creates - the previews it builds stay on
the previews page, same as any other. Run it, or at least the fast
path, after changing anything under `PreviewEnv`, `ConfigOverrides`,
`HostRouter`, or `PreviewSignon` - the class of regression it exists for
(a login or routing path that works on integration but not locally, or
vice versa) won't show up in `bundle exec rspec` at all.

## Relationship with govuk-docker

Preview App is a deliberately separate tool from
[govuk-docker](https://github.com/alphagov/govuk-docker), not a
replacement for it - see [Architecture](architecture.md). The two are
designed to run side by side on the same machine:

- Preview App listens on port 8080, not 80, specifically so it doesn't
  contend with govuk-docker's own nginx-proxy for the host port.
- `bin/preview-build` defaults to checkouts under `$GOVUK_ROOT_DIR`
  (`~/govuk` by default), the same convention govuk-docker uses.
- Where an app needs the same fixture/setup data under Preview App as
  it does under govuk-docker (e.g. Whitehall's taxonomy), the manifest's
  `setup_tasks` mirror govuk-docker's own Makefile rather than
  reinventing it.
