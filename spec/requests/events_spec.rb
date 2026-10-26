require "rails_helper"

RSpec.describe "Events" do
  before { login_as(create(:user)) }

  def page
    Capybara::Node::Simple.new(response.body)
  end

  it "is linked from the header" do
    get previews_path

    expect(page).to have_link("Events", href: events_path)
  end

  it "lists events newest first, saying who did what to which preview, and when" do
    preview = create(:preview, app_name: "whitehall", branch: "my-branch")
    Event.record!(:created, preview, user: create(:user, email: "someone@example.com")).update!(created_at: 2.hours.ago)
    Event.record!(:slept, preview, automatic: true).update!(created_at: 1.hour.ago)
    Event.record!(:woken, preview)

    get events_path

    expect(response).to have_http_status(:ok)
    rows = page.all("table tbody tr").map { |row| row.all("td").drop(1).map(&:text) }
    expect(rows).to eq([
      ["Woken", "whitehall", "my-branch", "Anonymous"],
      ["Slept", "whitehall", "my-branch", "Automatic"],
      ["Created", "whitehall", "my-branch", "someone@example.com"],
    ])
    expect(page.all("table tbody tr").last.first("td")).to have_css("time", text: "about 2 hours ago")
  end

  it "says so when nothing has happened yet" do
    get events_path

    expect(response.body).to include("There are no events yet.")
  end
end
