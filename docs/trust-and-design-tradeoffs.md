# Trust and design trade-offs

This page is about the deliberate decisions behind who gets to see a
preview, what identity a previewed app sees, and why - not a full
security audit (see the project's own backlog for known gaps, e.g.
namespace-wide rather than per-stack network isolation).

## Every preview requires a real Signon session

GOV.UK's own [non-GOV.UK domain
policy](https://docs.publishing.service.gov.uk/repos/govuk-infrastructure/architecture/decisions/0012-non-govuk-domain-policy.html)
means a preview - which necessarily lives on a non-`gov.uk` hostname
(`*.govuk-preview-app.dev.gov.uk`/the equivalent on integration) - can't
simply be the real thing wearing a different domain; it has to be
gated. `HostRouter` is that gate: it requires a signed
`_govuk_preview_access` cookie, obtainable only by a real Signon login,
before it will proxy a request to *any* preview's pod at all - entirely
independent of whatever the previewed app's own login looks like.

This is deliberately the **one** gate, not a second one layered on top
of each app's own. An earlier design also had `GDS_SSO_STRATEGY=real` on
every previewed app's own pod, so a visitor's specific Signon identity
carried through into the app itself via a real per-app OAuth2 round
trip. It was reverted: `HostRouter`'s gate already closes the hole that
mechanism was for (nobody without a real Signon login can reach a
preview at all), and the per-app round trip needed a previewed app's own
pod to call back to Preview App over the network - which never reliably
worked locally, only on integration, and wasn't worth maintaining two
different code paths for.

## Previewed apps only ever see test data, never a real identity

Because of the above, every previewed app runs gds-sso's **mock**
strategy (`GDS_SSO_STRATEGY=mock`) - it signs straight in as a seeded
test user from the app's own `db/seeds.rb`, with no OAuth2 round trip at
all. The trade-off accepted here: a preview shows a generic test user
rather than the specific person who's actually looking at it. Given
`HostRouter`'s gate already establishes *that a real person with a real
Signon login is here*, carrying their specific identity any further in
was never the part doing the access-control work - so previewed apps
never handle a real Signon identity or real Signon-backed data at all,
only their own seeded test fixtures.

## Asset Manager's own gate

Asset Manager's own `MediaController` normally requires a real Signon
session to read a *draft* asset (e.g. a lead image still being edited in
Whitehall) - a second gate, on top of `HostRouter`'s. Previewed under
mock Signon, rendering several draft images on one page meant several
concurrent mock OAuth round trips racing each other, with some arriving
out of order and failing.

`ConfigOverrides` patches Asset Manager's `MediaController` to skip that
second gate entirely for GET/HEAD requests (the only verbs its
media-serving routes ever accept). This is safe specifically *because*
of two things that are true together: a preview's Asset Manager is only
ever reachable at an unguessable, randomised hostname (never linked from
anywhere outside its own stack), and nothing a preview ever serves is
real, sensitive GOV.UK content - it's either a fixture or something a
developer uploaded for testing. Neither holds for the real Asset
Manager on integration/production, which is exactly why this is a
preview-only patch, not a change proposed to Asset Manager itself.

## Why Preview App itself is different

Preview App's own login (signing into
`govuk-preview-app.integration.publishing.service.gov.uk` itself, to see
the previews list) is the one place in this whole system that *does* use
a real Signon session end to end, with no mock strategy involved - it's
a normal GOV.UK admin app, on a normal `publishing.service.gov.uk`
hostname, and the thing granting access to every preview besides. There
is no previewed-app trade-off to make here: this app isn't itself being
previewed.

## Further reading

- [Architecture](architecture.md) - where `HostRouter` and the
  `previews` namespace's own isolation fit together.
- [Troubleshooting](troubleshooting.md) - diagnosing a login failure,
  including telling a stale cookie from a real regression in any of the
  above.
