# typed: true

# Tiingo joins Alpha Vantage as a market-data integration: a per-household
# API key (encrypted at rest, editable from Settings → Integrations,
# testable) that the market-data router treats as the preferred candle
# source while it is configured.
class CreateTiingoConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :tiingo_configurations, id: :uuid do |t|
      t.text :api_key
      t.uuid :household_id, null: false
      t.timestamps
    end
    add_index :tiingo_configurations, :household_id, unique: true
    add_foreign_key :tiingo_configurations, :households, on_delete: :cascade
  end
end
