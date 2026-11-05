class CreateInvestmentTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :investment_transactions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :security, null: true, foreign_key: true
      t.references :transaction_type, null: false, foreign_key: true
      t.date :trade_date, null: false
      t.date :post_date
      t.date :settlement_date
      t.string :local_currency
      t.decimal :price_usd,        precision: 18, scale: 6
      t.decimal :price_local,      precision: 18, scale: 6
      t.decimal :quantity,         precision: 18, scale: 6
      t.decimal :cost_usd,         precision: 18, scale: 4
      t.decimal :cost_local,       precision: 18, scale: 4
      t.decimal :gl_short_usd,     precision: 18, scale: 4
      t.decimal :gl_short_local,   precision: 18, scale: 4
      t.decimal :gl_long_usd,      precision: 18, scale: 4
      t.decimal :gl_long_local,    precision: 18, scale: 4
      t.decimal :amount_usd,       precision: 18, scale: 4
      t.decimal :amount_local,     precision: 18, scale: 4
      t.decimal :income_usd,       precision: 18, scale: 4
      t.decimal :income_local,     precision: 18, scale: 4
      t.decimal :balance,          precision: 18, scale: 4
      t.decimal :commissions_usd,  precision: 18, scale: 4
      t.decimal :commissions_local, precision: 18, scale: 4
      t.string  :description
      t.string  :check_number
      t.decimal :tax_withheld,     precision: 18, scale: 4
      t.string  :source_row_hash, null: false

      t.timestamps
    end
    add_index :investment_transactions, :source_row_hash, unique: true
    add_index :investment_transactions, :trade_date
  end
end
