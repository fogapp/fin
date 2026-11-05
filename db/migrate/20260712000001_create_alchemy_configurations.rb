# Household-scoped Alchemy credentials (Portfolio API key) for on-chain
# wallet balance tracking. Mirrors coinbase_configurations.
class CreateAlchemyConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :alchemy_configurations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.text :api_key
      t.timestamps
      t.index :household_id
    end
    add_foreign_key :alchemy_configurations, :households, on_delete: :cascade
  end
end
