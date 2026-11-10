# Does a rollout restart on the deploy of the root app
# This is necessary to pick up config map changes
class PreviewRolloutRestarter
  ROLLOUT_RESTART = "Rollout Restarting...".freeze

  attr_reader :root

  def initialize(root)
    @root = root
  end

  def rollout_restart
    return unless root.running?

    root.update!(status_message: ROLLOUT_RESTART)

    root.update!(status_message: nil) if root.reload.running?
  end
end
