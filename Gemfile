source "https://rubygems.org"
ruby "~> 4.0"

gem "rails", "~> 8.1.3"

gem "bootsnap", require: false
gem "dartsass-rails"
gem "gds-sso"
gem "govuk_app_config"
gem "govuk_publishing_components", git: "https://github.com/alphagov/govuk_publishing_components.git", branch: "test-1-upgrade-to-govuk-frontend-6.2"
gem "govuk_sidekiq"
gem "pg", "~> 1.1"
gem "plek"
gem "puma", ">= 5.0"
gem "rack-proxy"
gem "sentry-sidekiq"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "factory_bot_rails"
  gem "govuk_test"
  gem "rubocop-govuk"
end

group :test do
  gem "rails-controller-testing"
  gem "rspec-rails"
  gem "webmock"
end
