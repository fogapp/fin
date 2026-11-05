# typed: true

# Moves the Alpha Vantage API key out of ENV and into a per-household
# integration record, matching the CoinMarketCap/Coinbase/Alchemy pattern
# (encrypted at rest, editable from Settings → Integrations, testable).
class CreateAlphaVantageConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :alpha_vantage_configurations, id: :uuid do |t|
      t.text :api_key
      t.uuid :household_id, null: false
      t.timestamps
    end
    add_index :alpha_vantage_configurations, :household_id, unique: true
    add_foreign_key :alpha_vantage_configurations, :households, on_delete: :cascade
  end
end
