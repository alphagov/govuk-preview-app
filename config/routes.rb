Rails.application.routes.draw do
  get "/healthcheck/live", to: proc { [200, {}, %w[OK]] }
  get "/healthcheck/ready", to: GovukHealthcheck.rack_response(
    GovukHealthcheck::ActiveRecord,
    GovukHealthcheck::SidekiqRedis,
  )

  # Where HostRouter sends a browser back once it has a real Preview App
  # session - see OauthController#continue.
  get "/oauth/continue", to: "oauth#continue"

  resources :previews, only: %i[index new create destroy] do
    member do
      # Named so as not to shadow Kernel#sleep, or Ruby's `retry` keyword.
      post :sleep, action: :put_to_sleep
      post :wake
      post :retry, action: :retry_build
      post :resize
      get :confirm_destroy
      get :confirm_rebuild
      post :rebuild
      get :logs
    end
  end

  # What previews have reserved, against the most they're allowed - see
  # ResourceUsage.
  resource :resources, only: :show

  # Who did what to which preview, and when - see Event.
  resources :events, only: :index

  root to: redirect("/previews")
end
