class CreateMarketPrices < ActiveRecord::Migration[8.1]
  def change
    create_table :market_prices do |t|
      t.references :security, null: false, foreign_key: true
      t.date    :date, null: false
      t.decimal :open,           precision: 18, scale: 6
      t.decimal :high,           precision: 18, scale: 6
      t.decimal :low,            precision: 18, scale: 6
      t.decimal :close,          precision: 18, scale: 6
      t.decimal :adjusted_close, precision: 18, scale: 6
      t.bigint  :volume

      t.timestamps
    end
    add_index :market_prices, [ :security_id, :date ], unique: true
  end
end
