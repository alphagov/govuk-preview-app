require "rails_helper"

RSpec.describe "Resources" do
  let(:api) { kubernetes_api }

  before do
    login_as(create(:user))
    allow(KubernetesApi).to receive(:new).and_return(api)
    stub_request(:get, k8s_url(api.path("v1", "resourcequotas", "previews"))).to_return(json_response({
      status: {
        hard: { "requests.memory" => "7Gi", "limits.memory" => "64Gi" },
        used: { "requests.memory" => "6656Mi", "limits.memory" => "4Gi" },
      },
    }))
    stub_request(:get, k8s_url(api.path("v1", "persistentvolumeclaims"))).to_return(json_response({ items: [] }))
  end

  def stub_pods(*pods)
    stub_request(:get, k8s_url(api.path("v1", "pods"))).to_return(json_response({ items: pods }))
  end

  def page
    Capybara::Node::Simple.new(response.body)
  end

  it "is linked from the header" do
    stub_pods
    get previews_path

    expect(page).to have_link("Resources", href: resources_path)
  end

  it "shows how much of each limit is reserved, saying when it's nearly full" do
    stub_pods

    get resources_path

    expect(response).to have_http_status(:ok)
    meters = page.all(".app-meter").map { |meter| meter.text.squish }
    expect(meters.first).to start_with("Memory reserved 6.5 GiB of 7 GiB (93%) Full")
    expect(meters.second).to start_with("Memory limits 4 GiB of 64 GiB (6%)")
    expect(page.find(".app-meter--danger .app-meter__fill")[:width]).to eq("93%")
  end

  it "breaks each stack down into its parts, with a total" do
    whitehall = create(:preview, app_name: "whitehall", branch: "my-branch", status: :running)
    stub_pods(
      { metadata: { name: "a", labels: KubernetesRunner.labels_for(whitehall, "web") },
        status: { phase: "Running" },
        spec: { containers: [{ resources: { requests: { memory: "288Mi" }, limits: { memory: "768Mi" } } }] } },
      { metadata: { name: "sink" },
        status: { phase: "Running" },
        spec: { containers: [{ resources: { requests: { memory: "16Mi" }, limits: { memory: "64Mi" } } }] } },
    )

    get resources_path

    stack = page.find(".app-resource-stack", text: "whitehall (my-branch)")
    expect(stack.all("tbody tr").map { |row| row.all("td, th").map(&:text).map(&:squish) }).to eq([
      ["whitehall", "web", "288 MiB", "768 MiB", ""],
      ["Total", "", "288 MiB", "768 MiB", ""],
    ])
    expect(response.body).to include("sink")
  end

  it "says so when Kubernetes can't be reached" do
    stub_request(:get, k8s_url(api.path("v1", "resourcequotas", "previews"))).to_raise(Errno::ECONNREFUSED)

    get resources_path

    expect(response).to have_http_status(:ok)
    expect(page).to have_text("Couldn't reach Kubernetes")
  end
end
