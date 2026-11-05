class CreateCreditCardTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_card_transactions do |t|
      t.date :transaction_date, null: false
      t.date :post_date
      t.string :description
      t.string :raw_category
      t.string :transaction_type
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.string :memo
      t.references :merchant, foreign_key: true
      t.string :source_row_hash, null: false
      t.timestamps
    end

    add_index :credit_card_transactions, :source_row_hash, unique: true
    add_index :credit_card_transactions, :transaction_date
  end
end
