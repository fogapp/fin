class CreatePositionSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :position_snapshots do |t|
      t.references :account, null: false, foreign_key: true
      t.references :security, null: false, foreign_key: true
      t.date    :as_of_date, null: false
      t.decimal :quantity,                 precision: 18, scale: 6
      t.decimal :price,                    precision: 18, scale: 6
      t.decimal :market_value,             precision: 18, scale: 4
      t.decimal :cost_basis,               precision: 18, scale: 4
      t.decimal :unit_cost,                precision: 18, scale: 6
      t.decimal :unrealized_gain_loss,     precision: 18, scale: 4
      t.decimal :unrealized_gain_loss_pct, precision: 10, scale: 4
      t.decimal :accrued_income,           precision: 18, scale: 4
      t.decimal :est_annual_income,        precision: 18, scale: 4
      t.decimal :dividend_yield,           precision: 10, scale: 4
      t.string  :asset_class
      t.string  :asset_strategy
      t.string  :asset_strategy_detail
      t.date    :acquisition_date
      t.string  :source_row_hash, null: false

      t.timestamps
    end
    add_index :position_snapshots, [ :account_id, :security_id, :as_of_date ], unique: true, name: "idx_pos_snap_unique"
    add_index :position_snapshots, :as_of_date
    add_index :position_snapshots, :source_row_hash, unique: true
  end
end
