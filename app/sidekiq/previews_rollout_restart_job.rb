class PreviewsRolloutRestartJob < JobBase
  def perform(preview_id)
    PreviewRolloutRestarter.new(Preview.find(preview_id)).rollout_restart!
  end
end
