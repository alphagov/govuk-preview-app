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

  describe "pagination" do
    let(:per_page) { EventsController::PER_PAGE }

    def record_events(count)
      preview = create(:preview)
      count.times { |n| Event.record!(:created, preview).update!(created_at: n.minutes.ago) }
    end

    def listed_times
      page.all("table tbody tr time").map { |time| time["datetime"] }
    end

    it "shows the newest page of events first, linking to older ones" do
      record_events(per_page + 1)

      get events_path

      expect(listed_times.size).to eq(per_page)
      expect(listed_times.first).to eq(Event.maximum(:created_at).iso8601)
      expect(page).to have_css(".govuk-pagination__next a[href='#{events_path(page: 2)}']", text: "2 of 2")
      expect(page).to have_no_css(".govuk-pagination__prev")
    end

    it "shows older events on later pages, linking back to newer ones" do
      record_events(per_page + 1)

      get events_path(page: 2)

      expect(listed_times).to eq([Event.minimum(:created_at).iso8601])
      expect(page).to have_css(".govuk-pagination__prev a[href='#{events_path(page: 1)}']", text: "1 of 2")
      expect(page).to have_no_css(".govuk-pagination__next")
    end

    it "doesn't paginate a single page of events" do
      record_events(per_page)

      get events_path

      expect(listed_times.size).to eq(per_page)
      expect(page).to have_no_css(".govuk-pagination")
    end

    it "shows the nearest real page for one that's out of range" do
      record_events(per_page + 1)

      get events_path(page: 99)
      expect(listed_times.size).to eq(1)

      get events_path(page: "nonsense")
      expect(listed_times.size).to eq(per_page)
    end
  end

  it "says so when nothing has happened yet" do
    get events_path

    expect(response.body).to include("There are no events yet.")
  end
end
