# typed: true

# PlaidConfiguration.current uses first_or_initialize, which assumes one row
# per household — the other three provider config tables (coinbase, alchemy,
# coin_market_cap) already enforce that with a unique index; plaid was the
# odd one out. Compact any duplicates first (keep the newest — the one most
# recently saved from the settings screen), then enforce uniqueness.
class EnforceSinglePlaidConfigurationPerHousehold < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DELETE FROM plaid_configurations older
      USING plaid_configurations newer
      WHERE older.household_id = newer.household_id
        AND (older.created_at, older.id) < (newer.created_at, newer.id)
    SQL

    remove_index :plaid_configurations, name: "index_plaid_configurations_on_household_id"
    add_index :plaid_configurations, :household_id, unique: true,
              name: "index_plaid_configurations_on_household_id"
  end

  def down
    remove_index :plaid_configurations, name: "index_plaid_configurations_on_household_id"
    add_index :plaid_configurations, :household_id,
              name: "index_plaid_configurations_on_household_id"
  end
end
