require "rails_helper"

RSpec.describe PreviewRebuilder do
  let(:api) { kubernetes_api }
  let(:root) { create(:preview, app_name: "whitehall", branch: "my-branch", status: :rebuilding, full_stack: true, env_digest: "old") }
  let!(:dependency) { create(:preview, app_name: "publishing-api", branch: "main", parent: root, status: :running) }
  let(:rebuilder) { described_class.new(root, api:) }
  let(:destroyer) { instance_double(PreviewDestroyer) }
  let(:builder) { instance_double(PreviewBuilder, build!: nil) }
  let(:old_pod) { { metadata: { name: "old-pod" }, status: { phase: "Running" } } }

  before do
    allow(rebuilder).to receive(:pause)
    allow(PreviewDestroyer).to receive(:new).with(root).and_return(destroyer)
    allow(destroyer).to receive(:stop!) { dependency.destroy! }
    allow(PreviewBuilder).to receive(:new).and_return(builder)
  end

  def stub_pods(*responses)
    stub_request(:get, k8s_url(api.path("v1", "pods"))).with(query: hash_including({}))
      .to_return(*responses.map { |pods| json_response({ items: pods }) })
  end

  def stub_claims(*responses)
    stub_request(:get, %r{#{Regexp.escape(k8s_url(api.path('v1', 'persistentvolumeclaims')))}/.+})
      .to_return(*responses)
  end

  it "tears the whole stack down, waits until it's really gone, then builds it again in place" do
    # The old pods and volumes take a while to go, as Kubernetes deletes
    # them in the background.
    stub_pods([old_pod], [])
    claims = stub_claims(json_response({}), json_response({}, status: 404))

    rebuilder.rebuild!

    expect(destroyer).to have_received(:stop!)
    expect(rebuilder).to have_received(:pause).at_least(:once)
    expect(claims).to have_been_requested.at_least_times(2)
    expect(PreviewBuilder).to have_received(:new).with(root)
    expect(builder).to have_received(:build!)
    expect(root.reload).to have_attributes(status: "queued", status_message: nil, env_digest: nil, full_stack: true)
  end

  it "waits on the database volumes of every preview in the old stack, not just the top-level one" do
    stub_pods([])
    database_claim = stub_request(:get, k8s_url(api.path("v1", "persistentvolumeclaims", "data-#{KubernetesDatabaseRunner.new(dependency, GovukApps.find('publishing-api').database).container_name}-0")))
      .to_return(json_response({}, status: 404))
    stub_claims(json_response({}, status: 404))

    rebuilder.rebuild!

    expect(database_claim).to have_been_requested
  end

  it "gives up, saying why, if the old stack hasn't gone in time - rather than building on top of it" do
    stub_pods([old_pod])
    stub_claims(json_response({}, status: 404))

    rebuilder.rebuild!(timeout: 0)

    expect(builder).not_to have_received(:build!)
    expect(root.reload.status).to eq("failed")
    expect(root.status_message).to start_with("Couldn't rebuild")
  end
end
