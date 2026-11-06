class EventsController < ApplicationController
  # Unlike previews, which what they can reserve between them keeps few,
  # events only ever accumulate - so they're shown a page at a time.
  PER_PAGE = 50

  def index
    @total_pages = [(Event.count / PER_PAGE.to_f).ceil, 1].max
    # A missing, nonsense or out-of-range page shows the nearest real one.
    @page = params[:page].to_i.clamp(1, @total_pages)
    @events = Event.order(created_at: :desc, id: :desc).limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end
end
