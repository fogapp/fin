require "factory_bot_rails"

RSpec.configure do |config|
  config.before(:suite) { FactoryBot.lint } if ENV["FACTORY_LINT"]
end
