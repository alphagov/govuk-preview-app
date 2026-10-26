class PreviewsRebuildJob < JobBase
  def perform(preview_id)
    preview = Preview.find(preview_id)
    PreviewRebuilder.new(preview).rebuild! if preview.rebuilding?
  end
end
