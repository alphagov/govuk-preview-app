require "rails_helper"

RSpec.describe PreviewsRefreshJob do
  it "delegates to PreviewRefresher for the given preview" do
    preview = create(:preview, app_name: "frontend", branch: "my-branch", status: :running)
    refresher = instance_double(PreviewRefresher, refresh!: nil)
    allow(PreviewRefresher).to receive(:new).with(preview).and_return(refresher)

    described_class.new.perform(preview.id)

    expect(refresher).to have_received(:refresh!)
  end
end
