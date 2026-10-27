require "rails_helper"

RSpec.describe GovukApps do
  describe ".all" do
    it "loads app definitions from config/govuk_apps.yml" do
      expect(described_class.all).not_to be_empty
      expect(described_class.all).to all(be_a(described_class::Definition))
    end
  end

  describe ".app_names" do
    it "includes frontend, publishing-api, whitehall, and their draft-stack counterparts" do
      expect(described_class.app_names).to include(
        "frontend", "draft-frontend", "content-store", "draft-content-store", "publishing-api", "whitehall",
        "govuk-publishing-components", "govuk-content-publishing-guidance",
        "collections", "feedback", "finder-frontend", "smart-answers", "places-manager",
        "locations-api", "local-links-manager", "support", "support-api"
      )
    end
  end

  describe ".find" do
    it "returns the definition for a known app, with no database/dependencies by default" do
      definition = described_class.find("collections")

      expect(definition.repo_url).to eq("https://github.com/alphagov/collections.git")
      expect(definition.port_env_var).to eq("PORT")
      expect(definition.env).to include("PLEK_SERVICE_CONTENT_STORE_URI" => "https://www.gov.uk/api")
      expect(definition.dependencies).to eq([])
      expect(definition.database).to be_nil
      expect(definition.setup_tasks).to eq([])
      expect(definition.worker_command).to be_nil
      expect(definition.env_aliases).to eq({})
    end

    it "returns false for publicly_readable when the manifest doesn't declare it" do
      expect(described_class.find("whitehall").publicly_readable).to be(false)
    end

    it "defaults a dependency to always running, without its own full-stack-mode-only dependencies" do
      expect(described_class.find("publisher").dependencies.map(&:to_h)).to eq([
        { app: "publishing-api", full_stack_mode_only: false, include_its_full_stack_dependencies_when_running_in_full_stack_mode: false },
      ])
    end

    it "declares every dependency with only known keys, as a typo would silently mean `false`" do
      described_class.app_names.each do |name|
        YAML.load_file(Rails.root.join("config/govuk_apps.yml")).dig(name, "dependencies")&.each do |dependency|
          expect(dependency.keys - described_class::Dependency.members.map(&:to_s)).to be_empty, "#{name}: #{dependency.inspect}"
          expect(dependency).to have_key("app")
        end
      end
    end

    it "parses a declared database" do
      definition = described_class.find("publishing-api")

      expect(definition.database).to have_attributes(adapter: "postgresql", image: "postgres:17")
    end

    it "parses declared dependencies, in order" do
      definition = described_class.find("whitehall")

      expect(definition.dependencies.map(&:to_h)).to eq([
        { app: "publishing-api", full_stack_mode_only: false, include_its_full_stack_dependencies_when_running_in_full_stack_mode: true },
        { app: "asset-manager", full_stack_mode_only: true, include_its_full_stack_dependencies_when_running_in_full_stack_mode: false },
        { app: "frontend", full_stack_mode_only: true, include_its_full_stack_dependencies_when_running_in_full_stack_mode: false },
        { app: "draft-frontend", full_stack_mode_only: true, include_its_full_stack_dependencies_when_running_in_full_stack_mode: false },
      ])
      expect(definition.database).to have_attributes(adapter: "mysql2", image: "mysql:8")
    end

    it "parses declared setup_tasks" do
      definition = described_class.find("whitehall")

      expect(definition.setup_tasks).to eq(%w[taxonomy:populate_end_to_end_test_data taxonomy:rebuild_cache])
    end

    it "parses a declared worker_command and dependency" do
      definition = described_class.find("publishing-api")

      expect(definition.worker_command).to eq(%w[bundle exec sidekiq -C ./config/sidekiq.yml])
      expect(definition.dependencies.map(&:app)).to eq(%w[content-store draft-content-store])
      expect(definition.dependencies.map(&:full_stack_mode_only)).to eq([true, true])
    end

    it "parses publicly_readable" do
      expect(described_class.find("content-store").publicly_readable).to be(true)
      expect(described_class.find("draft-content-store").publicly_readable).to be(true)
      expect(described_class.find("frontend").publicly_readable).to be(true)
      expect(described_class.find("draft-frontend").publicly_readable).to be(true)
      expect(described_class.find("publishing-api").publicly_readable).to be(false)
    end

    it "parses declared env_aliases" do
      expect(described_class.find("draft-frontend").env_aliases).to eq(
        "PLEK_SERVICE_CONTENT_STORE_URI" => "PLEK_SERVICE_DRAFT_CONTENT_STORE_URI",
      )
    end

    it "parses govuk-publishing-components, including its Procfile-only MAIN_COMPONENT_GUIDE flag" do
      definition = described_class.find("govuk-publishing-components")

      expect(definition.repo_url).to eq("https://github.com/alphagov/govuk_publishing_components.git")
      expect(definition.port_env_var).to eq("PORT")
      expect(definition.env).to eq(
        "GOVUK_WEBSITE_ROOT" => "https://www.gov.uk",
        "PLEK_SERVICE_CONTENT_STORE_URI" => "https://www.gov.uk/api",
        "PLEK_SERVICE_RUMMAGER_URI" => "https://www.gov.uk/api",
        "MAIN_COMPONENT_GUIDE" => "true",
        "RAILS_ENV" => "development",
        "RACK_ENV" => "development",
      )
    end

    it "parses govuk-content-publishing-guidance, a plain app with no extra env" do
      definition = described_class.find("govuk-content-publishing-guidance")

      expect(definition.repo_url).to eq("https://github.com/alphagov/govuk-content-publishing-guidance.git")
      expect(definition.port_env_var).to eq("PORT")
      expect(definition.env).to eq({})
    end

    it "parses collections" do
      definition = described_class.find("collections")

      expect(definition.repo_url).to eq("https://github.com/alphagov/collections.git")
      expect(definition.env).to eq(
        "GOVUK_APP_DOMAIN" => "www.gov.uk",
        "GOVUK_WEBSITE_ROOT" => "https://www.gov.uk",
        "PLEK_SERVICE_CONTENT_STORE_URI" => "https://www.gov.uk/api",
        "PLEK_SERVICE_SEARCH_API_URI" => "https://www.gov.uk/api",
      )
    end

    it "parses feedback" do
      definition = described_class.find("feedback")

      expect(definition.repo_url).to eq("https://github.com/alphagov/feedback.git")
      expect(definition.env).to eq(
        "GOVUK_APP_DOMAIN" => "www.gov.uk",
        "GOVUK_WEBSITE_ROOT" => "https://www.gov.uk",
        "PLEK_SERVICE_CONTENT_STORE_URI" => "https://www.gov.uk/api",
      )
    end

    it "parses finder-frontend" do
      definition = described_class.find("finder-frontend")

      expect(definition.repo_url).to eq("https://github.com/alphagov/finder-frontend.git")
      expect(definition.env).to eq(
        "GOVUK_APP_DOMAIN" => "www.gov.uk",
        "GOVUK_WEBSITE_ROOT" => "https://www.gov.uk",
        "PLEK_SERVICE_CONTENT_STORE_URI" => "https://www.gov.uk/api",
        "PLEK_SERVICE_SEARCH_API_URI" => "https://www.gov.uk/api",
        "PLEK_SERVICE_WHITEHALL_FRONTEND_URI" => "https://www.gov.uk",
      )
    end

    it "parses places-manager" do
      definition = described_class.find("places-manager")

      expect(definition.repo_url).to eq("https://github.com/alphagov/places-manager.git")
      expect(definition.database.adapter).to eq("postgis")
      # Built on the official postgres image, whose entrypoint runs as the
      # database pod's non-root user and honours KubernetesDatabaseRunner's
      # env and args (unlike e.g. kartoza/postgis, which needs root).
      expect(definition.database.image).to eq("imresamu/postgis:18-3.6")
      expect(definition.worker_command).to eq(["bundle", "exec", "sidekiq", "-C", "./config/sidekiq.yml"])
      expect(definition.publicly_readable).to be(true)
      expect(definition.public_paths).to be_nil
      expect(definition.env).to eq(
        "DISABLE_SECURE_COOKIES" => "1",
        "GOVUK_WEBSITE_ROOT" => "https://www.gov.uk",
        "PLEK_SERVICE_CONTENT_STORE_URI" => "https://www.gov.uk/api",
        "PLEK_SERVICE_SEARCH_API_URI" => "https://www.gov.uk/api",
      )
    end

    it "parses locations-api" do
      definition = described_class.find("locations-api")

      expect(definition.repo_url).to eq("https://github.com/alphagov/locations-api.git")
      expect(definition.database.adapter).to eq("postgresql")
      expect(definition.worker_command).to be_nil
    end

    it "parses local-links-manager" do
      definition = described_class.find("local-links-manager")

      expect(definition.repo_url).to eq("https://github.com/alphagov/local-links-manager.git")
      expect(definition.database.adapter).to eq("postgresql")
      expect(definition.setup_tasks).to eq(%w[import:local_authorities:import_all])
      expect(definition.env).to eq("PLEK_SERVICE_PUBLISHING_API_URI" => "http://sink")
    end

    it "parses smart-answers" do
      definition = described_class.find("smart-answers")

      expect(definition.repo_url).to eq("https://github.com/alphagov/smart-answers.git")
      expect(definition.env).to eq(
        "GOVUK_APP_DOMAIN" => "www.gov.uk",
        "GOVUK_WEBSITE_ROOT" => "https://www.gov.uk",
        "PLEK_SERVICE_CONTENT_STORE_URI" => "https://www.gov.uk/api",
      )
    end

    it "parses support, which has no database but runs alongside Support API" do
      definition = described_class.find("support")

      expect(definition.repo_url).to eq("https://github.com/alphagov/support.git")
      expect(definition.database).to be_nil
      expect(definition.dependencies.map(&:to_h)).to eq([
        { app: "support-api", full_stack_mode_only: false, include_its_full_stack_dependencies_when_running_in_full_stack_mode: false },
      ])
      expect(definition.worker_command).to eq(["bundle", "exec", "sidekiq", "-C", "./config/sidekiq.yml"])
      expect(definition.env.keys).to contain_exactly("DISABLE_SECURE_COOKIES", "EMERGENCY_CONTACT_DETAILS")
      expect(JSON.parse(definition.env["EMERGENCY_CONTACT_DETAILS"])).to include("current_at")
    end

    it "parses support-api" do
      definition = described_class.find("support-api")

      expect(definition.repo_url).to eq("https://github.com/alphagov/support-api.git")
      expect(definition.database.adapter).to eq("postgresql")
      expect(definition.setup_tasks).to eq(%w[api_sync:import_organisations])
      expect(definition.publicly_readable).to be(false)
      expect(definition.env).to eq(
        "DISABLE_ZENDESK" => "1",
        "GOVUK_WEBSITE_ROOT" => "https://www.gov.uk",
        "PLEK_SERVICE_CONTENT_STORE_URI" => "https://www.gov.uk/api",
      )
    end

    it "returns nil for an unknown app" do
      expect(described_class.find("not-a-real-app")).to be_nil
    end

    it "raises if the manifest ever declares a repo_url outside the alphagov org" do
      described_class.instance_variable_set(:@all, nil)
      allow(YAML).to receive(:load_file).and_return(
        "evil-app" => { "repo_url" => "https://github.com/not-alphagov/evil.git", "port_env_var" => "PORT" },
      )

      expect { described_class.all }.to raise_error(/untrusted repo_url/)

      described_class.instance_variable_set(:@all, nil)
    end
  end

  describe ".trusted_repo_url?" do
    it "is true for a real alphagov GitHub repo" do
      expect(described_class.trusted_repo_url?("https://github.com/alphagov/whitehall.git")).to be(true)
    end

    it "is false for a different org" do
      expect(described_class.trusted_repo_url?("https://github.com/not-alphagov/whitehall.git")).to be(false)
    end

    it "is false for a lookalike host" do
      expect(described_class.trusted_repo_url?("https://github.com.evil.com/alphagov/whitehall.git")).to be(false)
    end

    it "is false for a userinfo trick pointing at a different real host" do
      expect(described_class.trusted_repo_url?("https://github.com@evil.com/alphagov/whitehall.git")).to be(false)
    end

    it "is false for plain http" do
      expect(described_class.trusted_repo_url?("http://github.com/alphagov/whitehall.git")).to be(false)
    end

    it "is false for a malformed URL" do
      expect(described_class.trusted_repo_url?("not a url")).to be(false)
    end
  end

  describe ".dependency_tree" do
    it "lists every transitive dependency, in build order" do
      expect(described_class.dependency_tree("whitehall")).to eq(
        %w[publishing-api content-store draft-content-store asset-manager frontend draft-frontend],
      )
    end

    it "leaves out a dependency's own full-stack-mode-only dependencies unless it's declared to include them - e.g. Frontend's, in Whitehall's full stack" do
      expect(described_class.dependency_tree("frontend")).to eq(%w[locations-api local-links-manager places-manager])
      expect(described_class.dependency_tree("frontend", full_stack: false)).to eq([])
    end

    it "leaves out full-stack-only dependencies, at any depth, for a core stack" do
      expect(described_class.dependency_tree("whitehall", full_stack: false)).to eq(%w[publishing-api])
    end

    it "parses each app's, and its database's, memory settings" do
      whitehall = described_class.find("whitehall")

      expect(whitehall.memory).to eq("request" => "288Mi", "limit" => "768Mi")
      expect(whitehall.database.memory).to eq("request" => "224Mi", "limit" => "512Mi")
    end

    it "parses resync_tasks" do
      expect(described_class.find("publishing-api").resync_tasks).to eq(%w[represent_downstream:all])
    end
  end

  describe ".full_stack_option? and .full_stack_extras" do
    it "lists what an app's own full stack adds - e.g. Whitehall's Frontends, and Publishing API's Content Stores" do
      expect(described_class.full_stack_extras("whitehall")).to eq(%w[content-store draft-content-store asset-manager frontend draft-frontend])
      expect(described_class.full_stack_extras("publishing-api")).to eq(%w[content-store draft-content-store])
      expect(described_class.full_stack_option?("whitehall")).to be(true)
    end

    it "offers a full stack only to apps that declare one themselves, not just by depending on one that does" do
      expect(described_class.full_stack_option?("publishing-api")).to be(true)
      expect(described_class.full_stack_option?("content-store")).to be(false)
    end

    it "offers Frontend a full stack of its postcode lookups" do
      expect(described_class.full_stack_extras("frontend")).to eq(%w[locations-api local-links-manager places-manager])
      expect(described_class.full_stack_option?("frontend")).to be(true)
    end

    it "offers no full stack for an app whose full stack is no different" do
      expect(described_class.full_stack_extras("draft-frontend")).to eq([])
      expect(described_class.full_stack_option?("draft-frontend")).to be(false)
    end
  end
end
