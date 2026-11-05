class AddTransactionSyncToAlchemyConfigurations < ActiveRecord::Migration[8.1]
  def change
    change_table :alchemy_configurations, bulk: true do |t|
      t.boolean  :transactions_enabled, null: false, default: false
      t.string   :sync_frequency, null: false, default: "daily"
      t.text     :auth_token   # Notify dashboard-API token (encrypted), distinct from api_key
      t.string   :webhook_base_url
      t.datetime :transactions_last_synced_at
    end
  end
end
