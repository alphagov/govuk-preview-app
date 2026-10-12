# Troubleshooting

## A code change isn't taking effect on an existing preview

`ConfigOverrides`'s content, and every env var `PreviewEnv` sets, are
baked into a preview's pod **once, at creation** - via a ConfigMap
(`KubernetesRunner#prepare!`) and the pod spec's own env, respectively.
Redeploying Preview App itself (`bin/kind-deploy`) changes what *new*
previews get; it never reaches back into one that's already running.

If you've changed either of those and a specific existing preview still
behaves the old way: destroy and recreate it (or just that dependency,
if the change only affects one). There's no in-place refresh for this -
treat it the same as any other "the pod needs a new image" change.

## `*.dev.gov.uk` isn't resolving

Locally, this domain only resolves at all because of your own machine's
dnsmasq rule (see
[Local development](local-development.md#prerequisites)) - pods inside
the cluster never go through it, only your own browser/`curl`/the host
machine generally. If a preview's hostname won't resolve from your
browser but the cluster itself looks healthy (`kubectl --context
kind-govuk-preview-app -n previews get pods`), check that rule is
actually in place and dnsmasq has been restarted since.

## "There was a problem logging you into the application"

This generic page is gds-sso's own OmniAuth failure page
(`/auth/failure`) - it doesn't say what actually went wrong, only that
the OAuth2 callback failed. Before assuming it's a code regression:

1. **Try a fresh login in an incognito/private window.** A session
   cookie that can't be read back (most commonly because the app's pod
   restarted - rotating what it uses to encrypt sessions - between you
   starting the login and Signon redirecting back) produces exactly
   this page, and clearing cookies fixes it immediately. This is by far
   the most common cause, especially right after a redeploy.
2. If it persists after a clean login, check the failing app's own
   Rails logs for the real underlying OmniAuth error (e.g. `undefined
   method 'bytesize' for nil` is the same "missing session state"
   problem as above, just surfaced as a raw exception instead of
   OmniAuth's usual "invalid credentials" message).
3. If this is Preview App's *own* login (not a previewed app's), see
   [Trust and design trade-offs](trust-and-design-tradeoffs.md#why-preview-app-itself-is-different)
   - it's the one place using a real Signon session, so check Signon's
   own registration for it before assuming the bug is here.
4. If this is a *previewed* app's own login, note that it shouldn't be
   using real Signon at all locally or on integration - every previewed
   app runs gds-sso's mock strategy (see
   [Trust and design trade-offs](trust-and-design-tradeoffs.md#previewed-apps-only-ever-see-test-data-never-a-real-identity)).
   Seeing a real OAuth2 failure page for a *previewed* app at all would
   itself be the regression worth chasing.

## A preview is stuck "waiting for room"

The `previews` namespace's `ResourceQuota` is shared by everyone -
`PreviewCapacity` tries to put the least-recently-used *other* stacks to
sleep to make room before giving up (see
[Sleeping and waking](preview-lifecycle.md#sleeping-and-waking)). If
nothing's been freed:

- Locally, this usually just means Docker Desktop doesn't have enough
  memory allocated for what you're asking for - check `bin/preview-usage`
  against `kubernetes/local/kustomization.yaml`'s quota.
- On integration, it genuinely means the namespace is full - someone
  else's recently-used stack is occupying the room; waking it isn't
  going to help, something has to be put to sleep (manually, from the
  previews page) or finished with first.

## `kind` cluster oddities

- If `bin/kind-deploy` can't reach the Docker daemon or buildx state at
  all, check Docker Desktop is actually running - a stale/orphaned `kind`
  cluster after a Docker restart can leave kubectl pointing at a context
  that no longer resolves.
- `bin/kind-down` is a full reset (deletes the cluster, every preview,
  and Preview App's own database) - reach for `bin/kind-deploy` first
  for "my code change isn't showing up," it's much cheaper.
- Every script here passes `--context kind-govuk-preview-app` on every
  `kubectl` call, specifically so a mistake here can never touch a real
  cluster - if you're debugging by hand, do the same.
