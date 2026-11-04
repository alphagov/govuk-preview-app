require "rails_helper"

RSpec.describe PreviewRefresher do
  let(:builder) { instance_double(PreviewBuilder, build!: nil) }
  let(:resolver) { instance_double(ImageResolver, resolve!: "ghcr.io/alphagov/govuk/whitehall:ddb8ad658f610fa0ccf7c92630a577ca0d004fe9") }
  let(:root) { create(:preview, app_name: "whitehall", branch: "my-branch", status: :running) }

  before do
    allow(ImageResolver).to receive(:new).and_return(resolver)
    allow(PreviewBuilder).to receive(:new).and_return(builder)
  end

  it "resolves its branch's latest image, then lets the builder move it onto that, keeping the rest of its stack" do
    described_class.new(root).refresh!

    expect(ImageResolver).to have_received(:new).with(GovukApps.find("whitehall"), "my-branch")
    expect(PreviewBuilder).to have_received(:new).with(root, image: "ghcr.io/alphagov/govuk/whitehall:ddb8ad658f610fa0ccf7c92630a577ca0d004fe9")
    expect(builder).to have_received(:build!)
    expect(root.reload).to have_attributes(status: "running", status_message: nil)
  end

  it "says it's refreshing while it waits for the image" do
    allow(resolver).to receive(:resolve!) do
      expect(root.reload.status_message).to eq(described_class::REFRESHING)
      "image"
    end

    described_class.new(root).refresh!
  end

  it "keeps running what it already has, saying why, when the new image never appears" do
    allow(resolver).to receive(:resolve!).and_raise(ImageResolver::ImageError, "No image was published")

    described_class.new(root).refresh!

    expect(root.reload).to have_attributes(status: "running", status_message: "Couldn't refresh: No image was published")
    expect(builder).not_to have_received(:build!)
  end

  it "does nothing to a preview that isn't running" do
    root.update!(status: :sleeping)

    described_class.new(root).refresh!

    expect(ImageResolver).not_to have_received(:new)
    expect(builder).not_to have_received(:build!)
  end
end
