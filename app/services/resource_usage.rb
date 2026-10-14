# What previews have reserved between them, against the namespace's
# ResourceQuota (see PreviewCapacity) - and what each stack reserves,
# part by part. For the Resources page.
#
# Reserved, not measured: what pods request (and are limited to), and what
# volumes claim, is what Kubernetes charges the quota for - so it's what
# decides when previews get put to sleep. (bin/preview-usage also shows
# what pods actually use.)
#
# Read from three calls - the quota, every pod and every volume claim -
# rather than per preview, so the page costs the same however many
# previews there are.
class ResourceUsage
  # The quota's resources, in the order they're shown - requests.memory
  # first, since it's the one that decides whether a preview gets room.
  QUOTA_RESOURCES = %w[requests.memory limits.memory requests.storage pods persistentvolumeclaims].freeze
  COUNTED_RESOURCES = %w[pods persistentvolumeclaims].freeze
  # How a stack's parts are ordered within each of its previews.
  COMPONENT_ORDER = %w[web worker task database storage redis].freeze

  # used/hard in MiB for memory and storage; a plain count otherwise.
  QuotaRow = Struct.new(:resource, :used, :hard, keyword_init: true) do
    def counted?
      COUNTED_RESOURCES.include?(resource)
    end
  end

  # One of a stack's apps' components (its web pod, its database and that
  # database's volume, ...) - or, for a part outside any stack, whatever
  # the pod or volume claim is named. All in MiB.
  Part = Struct.new(:preview, :name, :component, :request, :limit, :storage, keyword_init: true)

  Stack = Struct.new(:root, :parts, keyword_init: true) do
    def request = parts.sum(&:request)
    def limit = parts.sum(&:limit)
    def storage = parts.sum(&:storage)
  end

  attr_reader :quota, :stacks, :other

  def initialize(api: KubernetesApi.new)
    @api = api
    @quota = read_quota
    parts = (pod_parts + claim_parts).group_by { |part| [part.preview&.id || part.name, part.component] }
      .map { |_, same| merge(same) }
    in_stacks, @other = parts.partition(&:preview)
    @stacks = build_stacks(in_stacks)
  end

private

  attr_reader :api

  # Empty when there's no quota at all - then nothing limits previews.
  def read_quota
    status = api.get(api.path("v1", "resourcequotas", PreviewCapacity::QUOTA_NAME)).fetch("status", {})
    hard = status.fetch("hard", {})

    QUOTA_RESOURCES.filter_map do |resource|
      next unless hard.key?(resource)

      used = status.dig("used", resource) || "0"
      if COUNTED_RESOURCES.include?(resource)
        QuotaRow.new(resource:, used: used.to_i, hard: hard[resource].to_i)
      else
        QuotaRow.new(resource:, used: MemoryQuantity.to_mi(used), hard: MemoryQuantity.to_mi(hard[resource]))
      end
    end
  rescue KubernetesApi::NotFound
    []
  end

  # Only pods that haven't finished - finished ones no longer count
  # against the quota (as PreviewCapacity.pods_for).
  def pod_parts
    api.get(api.path("v1", "pods")).fetch("items", [])
      .reject { |pod| %w[Succeeded Failed].include?(pod.dig("status", "phase")) }
      .map do |pod|
        containers = pod.dig("spec", "containers").to_a
        part_for(
          pod.dig("metadata", "labels") || {}, pod.dig("metadata", "name"),
          request: containers.sum { |c| MemoryQuantity.to_mi(c.dig("resources", "requests", "memory") || "0") },
          limit: containers.sum { |c| MemoryQuantity.to_mi(c.dig("resources", "limits", "memory") || "0") }
        )
      end
  end

  # A database's volume claim comes from its StatefulSet's
  # volumeClaimTemplate, so has none of the preview's labels (and adding
  # them isn't possible - Kubernetes won't change an existing StatefulSet's
  # templates). It's found by the name Kubernetes gives it instead, and
  # counted as part of the database.
  def claim_parts
    database_claims = previews_with_databases.index_by do |preview|
      "data-#{KubernetesDatabaseRunner.new(preview, GovukApps.find(preview.app_name).database).container_name}-0"
    end

    api.get(api.path("v1", "persistentvolumeclaims")).fetch("items", []).map do |claim|
      name = claim.dig("metadata", "name")
      storage = MemoryQuantity.to_mi(claim.dig("spec", "resources", "requests", "storage") || "0")

      if (preview = database_claims[name])
        Part.new(preview:, name: preview.app_name, component: "database", request: 0, limit: 0, storage:)
      else
        part_for(claim.dig("metadata", "labels") || {}, name, storage:)
      end
    end
  end

  def part_for(labels, name, request: 0, limit: 0, storage: 0)
    preview = previews[labels["govuk-preview-app/preview-id"].to_i]
    Part.new(
      preview:,
      # Outside any preview, a pod's own name changes on every restart -
      # what it's an instance of is the steadier one to show.
      name: preview ? preview.app_name : labels.fetch("app.kubernetes.io/name", name),
      component: labels["govuk-preview-app/component"],
      request:, limit:, storage:
    )
  end

  # The same part counted more than once - e.g. two web pods mid-rollout,
  # both holding memory, or a database's pod and its volume.
  def merge(parts)
    parts.first.dup.tap do |part|
      part.request = parts.sum(&:request)
      part.limit = parts.sum(&:limit)
      part.storage = parts.sum(&:storage)
    end
  end

  # Every top-level preview, with whatever its stack holds - largest
  # first. One holding nothing (e.g. still queued) is listed too.
  def build_stacks(parts)
    by_root = parts.group_by { |part| part.preview.root.id }

    Preview.where(parent_id: nil).map { |root|
      order = root.tree.map(&:id)
      stack_parts = by_root.fetch(root.id, []).sort_by do |part|
        [order.index(part.preview.id) || order.size, COMPONENT_ORDER.index(part.component) || COMPONENT_ORDER.size]
      end
      Stack.new(root:, parts: stack_parts)
    }.sort_by { |stack| [-stack.request, -stack.storage, stack.root.id] }
  end

  def previews
    @previews ||= Preview.includes(:parent).index_by(&:id)
  end

  def previews_with_databases
    previews.values.select { |preview| GovukApps.find(preview.app_name)&.database }
  end
end
