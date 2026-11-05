# frozen_string_literal: true

# Plaid retired its "development" stack; its credentials now work against
# production. Rows still naming it would point the client at nothing.
class RetirePlaidDevelopmentEnvironment < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE plaid_configurations SET environment = 'production' WHERE environment = 'development'"
  end

  def down
    # Nothing to restore: "development" is no longer a valid Plaid stack.
  end
end
