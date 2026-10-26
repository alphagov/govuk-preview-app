# Rebuilds a top-level preview from scratch, in place: everything its stack
# runs (dependencies, databases and all) is deleted, then built again from
# its branch's latest image, the same as when it was first created. Its own
# record stays, so it keeps its id, URL, events and full stack choice.
#
# Kubernetes deletes pods and volumes in the background, and a rebuilt
# stack reuses the very same object names (they come from the slug) - so
# this waits until the old stack has really gone before building again.
# Otherwise, for instance, a new database pod could be handed the old
# volume while it's still being deleted.
class PreviewRebuilder
  class StillRunningError < StandardError; end

  attr_reader :root

  def initialize(root, api: KubernetesApi.new)
    @root = root
    @api = api
  end

  def rebuild!(timeout: 300)
    begin
      tear_down!(timeout:)
    rescue StillRunningError, KubernetesApi::Error => e
      root.update!(status: :failed, status_message: "Couldn't rebuild: #{e.message}".truncate(255))
      return
    end

    # Reloaded, so the build doesn't see the dependents just destroyed.
    root.reload.update!(status: :queued, status_message: nil, container_id: nil, env_digest: nil)
    PreviewBuilder.new(root).build!
  end

private

  attr_reader :api

  def tear_down!(timeout:)
    # Collected first - the dependents' records go with their objects.
    previews = root.tree
    claims = previews.flat_map { |preview| claim_names(preview) }

    PreviewDestroyer.new(root).stop!

    deadline = Time.current + timeout
    until gone?(previews, claims)
      raise StillRunningError, "the old preview was still shutting down after #{timeout} seconds" if Time.current > deadline

      pause
    end
  end

  # Nothing to wait for on an app since removed from the manifest - there's
  # no telling which volumes it had.
  def claim_names(preview)
    return [] unless preview.app_known?

    database = GovukApps.find(preview.app_name).database
    names = KubernetesRunner.new(preview).claim_names
    database ? [*names, KubernetesDatabaseRunner.new(preview, database).claim_name] : names
  end

  def gone?(previews, claims)
    PreviewCapacity.pods_for(api, previews).empty? &&
      claims.none? { |name| api.exists?(api.path("v1", "persistentvolumeclaims", name)) }
  end

  def pause
    sleep 3
  end
end
