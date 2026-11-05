# typed: true

# Per-household RentCast credentials, matching the Tiingo/Alpha Vantage
# integration pattern, plus the request counter the weekly sync budgets
# against. RentCast's free tier allows 50 requests per calendar month, so
# the counter is not decoration — it's what keeps the fan-out from
# overrunning the plan mid-month.
class CreateRentcastConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :rentcast_configurations, id: :uuid do |t|
      t.text :api_key
      t.uuid :household_id, null: false
      t.integer :monthly_request_limit, null: false, default: 50
      t.integer :requests_used, null: false, default: 0
      # First day of the month the counter covers; a later date rolls it.
      t.date :quota_period_start
      t.string :sync_frequency, null: false, default: "weekly"
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :rentcast_configurations, :household_id, unique: true
    add_foreign_key :rentcast_configurations, :households, on_delete: :cascade
  end
end
