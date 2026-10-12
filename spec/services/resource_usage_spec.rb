require "rails_helper"

RSpec.describe ResourceUsage do
  let(:api) { kubernetes_api }

  def stub_quota(hard:, used:)
    stub_request(:get, k8s_url(api.path("v1", "resourcequotas", "previews"))).to_return(json_response({ status: { hard:, used: } }))
  end

  def stub_pods(*pods)
    stub_request(:get, k8s_url(api.path("v1", "pods"))).to_return(json_response({ items: pods }))
  end

  def stub_claims(*claims)
    stub_request(:get, k8s_url(api.path("v1", "persistentvolumeclaims"))).to_return(json_response({ items: claims }))
  end

  def pod(preview, component, request:, limit:, phase: "Running")
    {
      metadata: { name: "pod-#{SecureRandom.hex(3)}", labels: KubernetesRunner.labels_for(preview, component) },
      status: { phase: },
      spec: { containers: [{ resources: { requests: { memory: request }, limits: { memory: limit } } }] },
    }
  end

  def claim(name, storage, labels: {})
    { metadata: { name:, labels: }, spec: { resources: { requests: { storage: } } } }
  end

  def database_claim_name(preview)
    "data-#{KubernetesDatabaseRunner.new(preview, GovukApps.find(preview.app_name).database).container_name}-0"
  end

  def usage
    described_class.new(api:)
  end

  before do
    stub_quota(hard: {}, used: {})
    stub_pods
    stub_claims
  end

  describe "#quota" do
    it "reads each limit and what's used of it, memory and storage in MiB, in a fixed order" do
      stub_quota(
        hard: { "pods" => "150", "limits.memory" => "64Gi", "requests.memory" => "7Gi", "requests.storage" => "60Gi" },
        used: { "requests.memory" => "1536Mi", "limits.memory" => "4Gi", "pods" => "9" },
      )

      expect(usage.quota.map(&:to_h)).to eq([
        { resource: "requests.memory", used: 1536, hard: 7168 },
        { resource: "limits.memory", used: 4096, hard: 65_536 },
        { resource: "requests.storage", used: 0, hard: 61_440 },
        { resource: "pods", used: 9, hard: 150 },
      ])
    end

    it "is empty when there's no quota" do
      stub_request(:get, k8s_url(api.path("v1", "resourcequotas", "previews"))).to_return(status: 404)

      expect(usage.quota).to eq([])
    end
  end

  describe "#stacks" do
    it "breaks each stack down into its previews' parts, in build order, largest stack first" do
      small = create(:preview, app_name: "frontend", status: :running)
      whitehall = create(:preview, app_name: "whitehall", status: :running)
      publishing_api = create(:preview, app_name: "publishing-api", branch: "main", parent: whitehall, status: :running)
      stub_pods(
        pod(small, "web", request: "176Mi", limit: "512Mi"),
        pod(whitehall, "redis", request: "32Mi", limit: "128Mi"),
        pod(publishing_api, "web", request: "256Mi", limit: "768Mi"),
        pod(whitehall, "web", request: "288Mi", limit: "768Mi"),
        pod(whitehall, "database", request: "224Mi", limit: "512Mi"),
      )
      stub_claims(claim(database_claim_name(whitehall), "1Gi"))

      stacks = usage.stacks

      expect(stacks.map(&:root)).to eq([whitehall, small])
      expect(stacks.first.parts.map { |part| [part.name, part.component, part.request, part.limit, part.storage] }).to eq([
        ["whitehall", "web", 288, 768, 0],
        ["whitehall", "database", 224, 512, 1024],
        ["whitehall", "redis", 32, 128, 0],
        ["publishing-api", "web", 256, 768, 0],
      ])
      expect(stacks.first).to have_attributes(request: 800, limit: 2176, storage: 1024)
    end

    it "keeps a sleeping stack's storage, though it holds no memory" do
      sleeping = create(:preview, app_name: "whitehall", status: :sleeping)
      stub_claims(claim(database_claim_name(sleeping), "1Gi"))

      expect(usage.stacks.first).to have_attributes(root: sleeping, request: 0, storage: 1024)
    end

    it "counts a shared volume by its labels" do
      whitehall = create(:preview, app_name: "whitehall", status: :running)
      stub_claims(claim("uploads", "2Gi", labels: KubernetesRunner.labels_for(whitehall, "storage")))

      expect(usage.stacks.first.parts.map { |part| [part.component, part.storage] }).to eq([["storage", 2048]])
    end

    it "adds up the same part counted more than once (e.g. two web pods mid-rollout)" do
      preview = create(:preview, app_name: "frontend", status: :running)
      stub_pods(pod(preview, "web", request: "176Mi", limit: "512Mi"), pod(preview, "web", request: "176Mi", limit: "512Mi"))

      expect(usage.stacks.first.parts.map(&:request)).to eq([352])
    end

    it "ignores finished pods, which no longer count against the quota" do
      preview = create(:preview, app_name: "frontend", status: :running)
      stub_pods(pod(preview, "task", request: "176Mi", limit: "512Mi", phase: "Succeeded"))

      expect(usage.stacks.first.parts).to eq([])
    end

    it "lists a stack holding nothing yet" do
      preview = create(:preview, app_name: "frontend", status: :queued)

      expect(usage.stacks.map(&:root)).to eq([preview])
    end
  end

  describe "#other" do
    it "holds what isn't part of any preview, by name - so everything adds up to the quota's used" do
      stub_pods({ metadata: { name: "sink-abc", labels: { "app.kubernetes.io/name" => "previews-sink" } }, status: { phase: "Running" }, spec: { containers: [{ resources: { requests: { memory: "16Mi" }, limits: { memory: "64Mi" } } }] } })
      stub_claims(claim("leftover", "1Gi"))

      expect(usage.other.map { |part| [part.name, part.request, part.storage] }).to eq([["previews-sink", 16, 0], ["leftover", 0, 1024]])
    end
  end
end
