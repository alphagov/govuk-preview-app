# The app manifest

`config/govuk_apps.yml` (parsed by `lib/govuk_apps.rb`) lists every app
Preview App can preview. It's a small manifest Preview App owns itself -
not a file each previewable app's own repo has to carry. Every entry's
`repo_url` must be `https://github.com/alphagov/<repo>` -
`GovukApps.trusted_repo_url?` enforces this at boot, raising rather than
booting with an untrusted entry, since an app's own image is run
unprivileged but is still arbitrary code in the cluster.

## Keys, in full

- **`repo_url`** - where the app's image comes from (see
  [Image resolution](preview-lifecycle.md#image-resolution)). Must be
  `https://github.com/alphagov/...`.
- **`port_env_var`** - the env var name the app's own image reads to
  know what port to listen on (e.g. `PORT`).
- **`env`** - a fixed set of extra environment variables passed to the
  app's pods - e.g. pointing a read-only dependency (Frontend's own
  Content Store client, via Plek) at the real GOV.UK service instead of
  running a preview of it.
- **`dependencies`** - other manifest entries that must run as their own
  real, dedicated preview (never shared across parents) before this app
  starts - e.g. Whitehall needs a real, writable Publishing API, not the
  real GOV.UK one. See `PreviewBuilder`. Order matters: each dependency
  can see the resolved `PLEK_SERVICE_*_URI` of every dependency declared
  *before* it in the same list - so Whitehall's `frontend` dependency,
  declared after `publishing-api`, inherits the real local Content Store
  address that `publishing-api`'s own `content-store` dependency
  resolved, not Frontend's own static, real-GOV.UK default.
- **`database`** - the database this app needs (one per preview, never
  shared - see `KubernetesDatabaseRunner`). Omit entirely for apps with
  no database (e.g. Frontend).
- **`setup_tasks`** - `bin/rails` tasks to run, in order, as one-off
  Kubernetes Jobs after the database is seeded and before the app
  starts - e.g. the basic taxonomy Whitehall needs in Publishing API
  before a document can be tagged to a topic (matching how
  govuk-docker's own Makefile sets this up). A failing task fails the
  preview, with the task's error as its status message.
- **`worker_command`** - starts a second, long-running Deployment from
  the same image (e.g. Publishing API's Sidekiq worker, which actually
  pushes published content downstream to Content Store - without it,
  nothing ever leaves Publishing API's own database). See
  `KubernetesRunner#start_worker!`.
- **`publicly_readable: true`** - makes a *dependency* preview reachable
  at a short, randomised hostname (e.g. `content-store-mvym1ob...`)
  instead of its full, dependency-chain-shaped slug - see
  [Routing](architecture.md#routing). Only for read-only,
  non-state-mutating APIs. Has no effect on a preview with no parent (a
  standalone top-level preview already gets a perfectly good, readable
  hostname from its own slug).
- **`env_aliases`** - re-exposes one of the dependency addresses this
  app has been given (inherited, or its own) under a different env var
  key, for its own pods only - not propagated to siblings or the parent.
  Only applied when that address exists (e.g. only in a full stack, for
  a `full_stack_dependencies` entry). Needed when an app's own code
  reads a fixed env var name whichever instance it should talk to - e.g.
  draft-frontend is the same codebase as frontend, which only ever reads
  `PLEK_SERVICE_CONTENT_STORE_URI` (never the draft one); and Whitehall
  builds its "View on website"/"Preview on website" links from
  `GOVUK_WEBSITE_ROOT` and `PLEK_SERVICE_DRAFT_ORIGIN_URI`.
- **`full_stack_dependencies`** - like `dependencies`, but only started
  when a preview asks for its full stack (`Preview#full_stack`) - built
  after this app's `dependencies`, in order. See
  [Core and full stacks](preview-lifecycle.md#core-and-full-stacks).
- **`memory`** - what each of the app's pods (web, worker, and one-off
  tasks) requests and is limited to - and `database: memory:`, its
  database's. Requests are what Kubernetes schedules by and charges the
  `previews` quota for, so size them from real usage
  (`bin/preview-usage`): roughly 25% above what a lightly-used preview
  of the app uses once booted. Limits should leave 2-3x headroom for
  boot and spikes. Apps without one get a generous default (see
  `KubernetesRunner.memory_for`) until they've been measured.
- **`shared_volumes`** - directories an app's web and worker processes
  both need - e.g. Whitehall's web process saves an upload that its
  worker then sends to Asset Manager. An app with any runs its worker as
  a second container in its web pod rather than a separate Deployment,
  with each volume mounted at `path` in both. They start empty and are
  lost when the preview sleeps, unless `persistent: true`, which keeps
  one on a volume of its own (`size`, default `1Gi`) until the preview
  is deleted.
- **`self_url_env`** - names env vars to set to the preview's own public
  URL - see `PreviewEnv`.
- **`public_paths`** - limits a `publicly_readable` dependency's public
  hostname to GET/HEAD requests for paths starting with one of these -
  e.g. Asset Manager's assets, but not its API (see `HostRouter`).
- **`resync_tasks`** - `bin/rails` tasks to run when a running preview
  is switched to the full stack - e.g. Publishing API re-sending
  everything it holds to the Content Stores that have just been added.

## Adding a new app or dependency

1. Add an entry to `config/govuk_apps.yml`, alphabetically, with at
   least `repo_url` and `port_env_var`. Add `database`/`dependencies`/
   `worker_command` as needed - look at an existing entry with a similar
   shape first (e.g. a database-and-worker app like Publishing API, or a
   plain stateless one like Frontend).
2. Build and load a local image of it to test against, without needing
   to push anything: `bin/preview-build <app>` (see
   [Local development](local-development.md#previewing-local-code)).
   Create a preview of it with that `local:<tag>` branch.
3. Common gotchas, all fixed via `ConfigOverrides` rather than the app's
   own code (see its own comment block in
   `app/services/config_overrides.rb` for the full list and reasoning):
   - A production-only Content Security Policy blocking its own stack's
     Asset Manager/other previews' hostnames.
   - `database.yml` ignoring `DATABASE_URL` under `RAILS_ENV=production`.
   - `config.hosts` allow-listing only real GOV.UK hostnames, 403ing
     every preview subdomain.
   - `X-Sendfile`/`X-Accel-Redirect` headers Preview App's own reverse
     proxy (`HostRouter`) has no filesystem access to honour.
   If the new app hits one of these, it's very likely already handled -
   check there before patching the app itself.
4. If it needs its own gds-sso-gated internal check bypassing (the way
   Asset Manager's own draft-asset gate is), see
   [Trust and design trade-offs](trust-and-design-tradeoffs.md) for the
   reasoning before adding another one - it should be the exception, not
   the default.
5. Run `bundle exec rspec` and `bundle exec rubocop`, and - for anything
   touching `PreviewEnv`, `ConfigOverrides`, `HostRouter` or
   `PreviewSignon` - `bin/smoke-test` against your local kind cluster
   (see [Local development](local-development.md#smoke-testing-against-a-real-cluster)).
