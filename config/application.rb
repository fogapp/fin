require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_view/railtie"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../lib/middleware/static_cache_control"
require_relative "legacy_env"

module Fin
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # rubocop/ holds custom RuboCop cops that depend on `rubocop/cop/base`,
    # which isn't loaded during a normal Rails boot — autoloading it from
    # Zeitwerk would crash with NameError. The cops are required explicitly
    # by .rubocop.yml when rubocop runs.
    # middleware/ is required by hand below: the middleware stack is assembled
    # from real class objects at configuration time, before the autoloaders
    # exist, so the constant can't come from Zeitwerk.
    config.autoload_lib(ignore: %w[assets tasks rubocop middleware])

    # Keep the MCP tools off the eager-load path. Mcp::Tools::Base subclasses
    # ::MCP::Tool, so eager loading it would require the mcp gem (and
    # json_schemer, ~7 MB) into every web and worker process at boot — for an
    # endpoint that only POST /mcp reaches. Zeitwerk still autoloads these on
    # first reference; McpController's before_action requires the gem first.
    #
    # Note this leaves the directory outside the eager-load safety net: a
    # constant-resolution error in a tool surfaces on the first /mcp request
    # rather than at boot. The MCP request specs cover that path.
    initializer "fin.lazy_load_mcp_tools", after: :setup_main_autoloader, before: :eager_load! do
      Rails.autoloaders.main.do_not_eager_load("#{root}/app/domain/mcp")
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.eager_load_paths << Rails.root.join("extras")

    # The boot default zone. Requests and jobs run in the instance's own
    # setting (InstanceSetting.time_zone, Settings → Household → Time zone;
    # see config/initializers/instance_time_zone.rb), whose default matches
    # this; console and rake run in this one. Without a local zone the app
    # ran in UTC and every Date.current / Time.current day boundary flipped
    # at 4-5pm on the US west coast — evening transactions booked to the
    # next day, budget threshold checks compared the wrong month, snapshots
    # stamped the wrong day. Timestamps are still stored in UTC; raw-SQL
    # sites that bucket by day convert via AT TIME ZONE (see
    # AccountBalanceSnapshot.local_date_sql).
    config.time_zone = "America/Los_Angeles"

    # Gzip JSON responses at the app layer so payload size doesn't depend on
    # the fronting nginx's gzip config. Placed outside Rack::ConditionalGet /
    # Rack::ETag so ETags are computed over the stable uncompressed body and
    # 304s (both middleware-issued and the controller-level render_cached
    # ones) pass through without a wasted compression pass.
    config.middleware.insert_before Rack::ConditionalGet, Rack::Deflater

    # Keep the file server's far-future Cache-Control off the files in public/
    # that aren't digest stamped — above all index.html, which otherwise
    # outlives the hashed bundles it names and boots the SPA to a blank page
    # after a deploy. See the middleware for the full story.
    config.middleware.insert_before ActionDispatch::Static, Middleware::StaticCacheControl

    # Don't generate system test files.
    config.generators.system_tests = nil
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end
  end
end
