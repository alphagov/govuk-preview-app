class PreviewsRefreshJob < JobBase
  def perform(preview_id)
    PreviewRefresher.new(Preview.find(preview_id)).refresh!
  end
end
