require "spec_helper"
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Base.connection.execute("SELECT 1")
rescue => e
  if e.message.match?(/could not connect|connection refused|connection not established|no such file|server closed|database.*does not exist/i) ||
      e.class.name.match?(/PG::|NoDatabaseError|ConnectionNotEstablished/)
    abort <<~MSG
      \n[RSpec] Database is not available — aborting before running any specs.

      Error: #{e.class}: #{e.message.strip}

      Make sure Postgres is running:
        brew services start postgresql@17   # or your version
        pg_ctl status -D /opt/homebrew/var/postgresql@17

    MSG
  end
  raise
end

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveJob::TestHelper, type: :job

  # Reset class-level caches between examples so tests are order-independent
  config.after(:each) { Merchants::RuleMatcher.reset_cache }
end
