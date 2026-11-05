# Moves a running top-level preview onto its branch's latest image - e.g.
# after a push to the branch - without rebuilding its stack: PreviewBuilder
# migrates its database and restarts just its own pods on the new image
# (see PreviewBuilder#reconfigure!). Its dependencies, databases and
# everything published into them are kept as they are, and so is the old
# version, still running, if the new image never appears.
class PreviewRefresher
  REFRESHING = "Refreshing…".freeze

  attr_reader :root

  def initialize(root)
    @root = root
  end

  def refresh!
    return unless root.running?

    root.update!(status_message: REFRESHING)
    begin
      image = ImageResolver.new(GovukApps.find(root.app_name), root.branch).resolve!
    rescue ImageResolver::ImageError => e
      root.update!(status_message: "Couldn't refresh: #{e.message}".truncate(255))
      return
    end

    PreviewBuilder.new(root, image:).build!
    root.update!(status_message: nil) if root.reload.running?
  end
end
