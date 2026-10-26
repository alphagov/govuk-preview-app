# Something done to a preview, and who did it - see the Events page.
#
# Attributed to the Signon user who took the action. An event with no user
# is either anonymous (e.g. a visit that woke a preview, from someone this
# app has no User for) or automatic (e.g. PreviewCapacity putting a preview
# to sleep to make room for another).
class Event < ApplicationRecord
  enum :action, {
    created: "created",
    full_stack_added: "full_stack_added",
    full_stack_removed: "full_stack_removed",
    slept: "slept",
    woken: "woken",
    deleted: "deleted",
    rebuilt: "rebuilt",
  }

  def self.record!(action, preview, user: nil, automatic: false)
    create!(
      action:,
      preview_id: preview.id,
      app_name: preview.app_name,
      branch: preview.branch,
      user_email: user&.email,
      automatic:,
    )
  end

  def attribution
    return "Automatic" if automatic?

    user_email.presence || "Anonymous"
  end
end
