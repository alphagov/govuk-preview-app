# Emergency Banner

The cluster can be used to test the configMap version of the emergency banner. This relies on a configMap being made in the cluster. In our EKS clusters, Whitehall creates the empty configMap on boot if it's not present. But here we make the configMap at cluster startup (it's defined in [/kubernetes/previews/govuk-apps-emergency-banner.yaml](/kubernetes/previews/govuk-apps-emergency-banner.yaml)) so that we can run frontend apps that rely on it without starting up Whitehall.

The configMap is shared by the entire namespace, so you can test it with two minimum stack previews - one for Whitehall, one for Frontend.

1. Edit the emergency banner in Whitehall
2. Rollout-Restart the Frontend deploy: `kubectl --context kind-govuk-preview-app rollout restart deploy/<your deploy>`

The banner should now be visible in Frontend.
