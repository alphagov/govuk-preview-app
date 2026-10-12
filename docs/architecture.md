# Architecture

## Where this fits in the GOV.UK stack

Preview App is an orchestrator, not a build system: it runs the image a
branch's own CI has already built and pushed to
`ghcr.io/alphagov/govuk/<repo>` (see [Image resolution](#image-resolution)
below), alongside a dedicated copy of every service that app depends on.
Given an app and a branch, it gives you several isolated copies of parts
of the GOV.UK stack - e.g. several branches of Whitehall, each with its
own Publishing API, Content Stores, Frontends and databases - running
side by side, each at its own hostname.

It isn't a replacement for [govuk-docker](https://github.com/alphagov/govuk-docker),
which runs real, persistent, locally-built dev copies of GOV.UK apps.
Preview App runs disposable, already-built CI images instead, and is
deliberately designed to run alongside govuk-docker on the same machine -
see [Local development](local-development.md).

It runs the same way locally (in a [kind](https://kind.sigs.k8s.io/)
cluster) as on integration: a Rails app plus a Sidekiq worker, which never
builds or runs anything itself - it only asks the Kubernetes API to
create ordinary, unprivileged objects in a dedicated `previews` namespace.

## The `previews` namespace as a security boundary

This isn't just tidiness - a previewed app runs arbitrary branch code,
and the namespace is what contains it:

- Preview App's own service account can only manage objects in
  `previews` - not the real apps alongside it in `apps` on integration -
  and can't read Secrets at all (see `kubernetes/previews/role.yaml`).
- NetworkPolicies (`kubernetes/previews/network-policies.yaml`) let
  preview pods talk to each other, to DNS, and out to the public
  internet, and let only Preview App's own web pod in. They can't reach
  other namespaces, private address ranges, or the cloud metadata
  service.
- A `ResourceQuota` caps what every preview can use between them - see
  [the preview lifecycle](preview-lifecycle.md#sleeping-and-waking).
- Every preview pod runs as its image's own non-root user, with no
  Kubernetes API token of its own, under the `restricted` Pod Security
  standard - the namespace rejects anything else.

The NetworkPolicy above is namespace-wide, not per-stack: any preview pod
can currently reach any *other* preview's pods and (deliberately
uncredentialed, see [trust and design trade-offs](trust-and-design-tradeoffs.md))
databases. Nothing sensitive lives in there, but it's a known gap, not a
deliberate design choice - see the project's own backlog for tightening
this to per-stack isolation.

## Routing

`HostRouter`, a Rack middleware, inspects every request's `Host` header.
If it matches a `running` (or `sleeping`/`waking`) top-level preview's
hostname, it proxies straight to that preview's Kubernetes Service,
never touching Preview App's own Rails routes at all. Anything else -
Preview App's own UI, or an unmatched/stale subdomain - falls through to
Preview App's normal routing.

A dependency preview is internal-only by default - most (e.g. Publishing
API) are unauthenticated, state-mutating APIs with no business being
reachable from a browser. A manifest entry marked `publicly_readable:
true` (e.g. Content Store, Asset Manager) is the exception: it gets a
short, randomised hostname of its own (`Preview#generate_public_hostname`),
routable the same way, scoped to the GET/HEAD-only `public_paths` the
manifest declares for it.

`HostRouter` is also the one gate every preview sits behind, regardless
of the previewed app's own login - see
[trust and design trade-offs](trust-and-design-tradeoffs.md) for why.

## The sink

In a core stack (see [the preview lifecycle](preview-lifecycle.md#core-and-full-stacks)),
an app that would have used a left-out `full_stack_dependencies` entry is
pointed at `kubernetes/previews/sink.yaml` instead: a shared nginx
Deployment that returns an empty `200` for everything and keeps nothing.
Publishing API, for example, has no setting to stop it pushing content
downstream - so in a core stack it pushes to the sink instead of a real
Content Store, harmlessly.

## Further reading

- [The preview lifecycle](preview-lifecycle.md) - how a preview is
  actually built, core vs. full stacks, sleep/wake, teardown.
- [Trust and design trade-offs](trust-and-design-tradeoffs.md) - the
  Signon story, and why previewed apps only ever see test data.
- [The app manifest](manifest.md) - `config/govuk_apps.yml` key by key,
  and how to add a new app.
- [Local development](local-development.md) - running this locally,
  and alongside govuk-docker.
- [Troubleshooting](troubleshooting.md).
