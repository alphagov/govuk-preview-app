require "rails_helper"

RSpec.describe PreviewsRebuildJob do
  let(:rebuilder) { instance_double(PreviewRebuilder, rebuild!: nil) }

  before { allow(PreviewRebuilder).to receive(:new).and_return(rebuilder) }

  it "delegates to PreviewRebuilder for the given preview" do
    preview = create(:preview, app_name: "frontend", branch: "my-branch", status: :rebuilding)

    described_class.new.perform(preview.id)

    expect(PreviewRebuilder).to have_received(:new).with(preview)
    expect(rebuilder).to have_received(:rebuild!)
  end

  it "does nothing for a preview that's no longer waiting to be rebuilt - e.g. a job queued twice" do
    preview = create(:preview, app_name: "frontend", branch: "my-branch", status: :starting)

    described_class.new.perform(preview.id)

    expect(rebuilder).not_to have_received(:rebuild!)
  end
end
