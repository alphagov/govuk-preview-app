class ApplicationController < ActionController::Base
  include GDS::SSO::ControllerMethods

  before_action :authenticate_user!
  # Signon's own "signin" permission is only enough to view a preview (see
  # OauthController, which skips this) - using Preview App itself (creating,
  # destroying or otherwise managing previews) needs "admin" too. Here,
  # rather than per controller, so anything new is covered by default.
  before_action :authorise_admin!

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

private

  def authorise_admin!
    authorise_user!("admin")
  end
end
