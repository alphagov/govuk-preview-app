require "rails_helper"

RSpec.describe Event do
  describe ".record!" do
    it "records the action against the preview, attributed to the user who took it" do
      preview = create(:preview, app_name: "whitehall", branch: "my-branch")
      user = create(:user, email: "someone@example.com")

      event = described_class.record!(:created, preview, user:)

      expect(event).to have_attributes(
        action: "created",
        preview_id: preview.id,
        app_name: "whitehall",
        branch: "my-branch",
        user_email: "someone@example.com",
        automatic: false,
      )
      expect(event.created_at).to be_present
    end

    it "keeps the app and branch, so the event still makes sense once the preview is deleted" do
      preview = create(:preview, app_name: "whitehall", branch: "my-branch")
      event = described_class.record!(:deleted, preview, user: create(:user))

      preview.destroy!

      expect(event.reload).to have_attributes(app_name: "whitehall", branch: "my-branch")
    end

    it "rejects an unknown action" do
      expect { described_class.record!(:exploded, create(:preview)) }.to raise_error(ArgumentError)
    end
  end

  describe "#attribution" do
    it "is the user's email address" do
      expect(described_class.new(user_email: "someone@example.com").attribution).to eq("someone@example.com")
    end

    it "is Anonymous when there's no user" do
      expect(described_class.new.attribution).to eq("Anonymous")
    end

    it "says the Preview App did it, for an automatic action" do
      expect(described_class.new(automatic: true).attribution).to eq("Automatic")
    end
  end
end
