# Coinbase and CoinMarketCap configurations were global singletons: any
# authenticated household could read status of / overwrite any other
# household's API credentials. Scope them per household like Plaid.
class ScopeProviderConfigurationsToHousehold < ActiveRecord::Migration[8.1]
  def up
    add_reference :coinbase_configurations, :household,
                  type: :uuid, foreign_key: { on_delete: :cascade }, index: false
    add_reference :coin_market_cap_configurations, :household,
                  type: :uuid, foreign_key: { on_delete: :cascade }, index: false

    # Existing rows predate multi-tenancy; attribute them to the oldest
    # household (the only one in a single-tenant deploy).
    first_household = select_value("SELECT id FROM households ORDER BY created_at ASC LIMIT 1")
    if first_household
      execute "UPDATE coinbase_configurations SET household_id = '#{first_household}' WHERE household_id IS NULL"
      execute "UPDATE coin_market_cap_configurations SET household_id = '#{first_household}' WHERE household_id IS NULL"
    else
      execute "DELETE FROM coinbase_configurations"
      execute "DELETE FROM coin_market_cap_configurations"
    end

    change_column_null :coinbase_configurations, :household_id, false
    change_column_null :coin_market_cap_configurations, :household_id, false
    add_index :coinbase_configurations, :household_id, unique: true
    add_index :coin_market_cap_configurations, :household_id, unique: true
  end

  def down
    remove_reference :coinbase_configurations, :household
    remove_reference :coin_market_cap_configurations, :household
  end
end
