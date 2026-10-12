# GOV.UK Preview App

A lightweight orchestrator for running disposable, branch-specific
preview instances of GOV.UK applications on Kubernetes. Given an app and
a branch, it runs the image that branch's own CI already built, alongside
a dedicated copy of every service it depends on - so, for example,
several branches of Whitehall (each with its own Publishing API, Content
Stores, Frontends and databases) can be previewed side by side, each at
its own hostname.

It runs the same way locally (in a [kind](https://kind.sigs.k8s.io/)
cluster) as on integration, and doesn't depend on
[govuk-docker](https://github.com/alphagov/govuk-docker) - the two can
run side by side.

## Documentation

- [Architecture](docs/architecture.md) - where this fits in the GOV.UK
  stack, the `previews` namespace as a security boundary, routing.
- [The preview lifecycle](docs/preview-lifecycle.md) - how a preview is
  built, core vs. full stacks, sleeping/waking, tearing down.
- [Trust and design trade-offs](docs/trust-and-design-tradeoffs.md) -
  Signon, and why previewed apps only ever see test data.
- [The app manifest](docs/manifest.md) - `config/govuk_apps.yml` key by
  key, and how to add a new app or dependency.
- [Local development](docs/local-development.md) - prerequisites,
  running it locally, previewing local code, smoke-testing, and its
  relationship with govuk-docker.
- [Troubleshooting](docs/troubleshooting.md).

## Quickstart

```
bin/kind-up
```

Then visit <http://govuk-preview-app.dev.gov.uk:8080/previews>. See
[Local development](docs/local-development.md) for prerequisites and
everything else.

## Licence

[MIT License](LICENCE)
