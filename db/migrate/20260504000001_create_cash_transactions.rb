# frozen_string_literal: true

class CreateCashTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_transactions do |t|
      # Discriminator — string enum, no default (must be explicit)
      t.string :source, null: false

      # Shared columns
      t.references :account, foreign_key: true
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.references :category, foreign_key: true
      t.string :description
      t.references :merchant, foreign_key: true
      t.date :post_date
      t.string :source_row_hash, null: false
      t.date :transaction_date, null: false
      t.string :transaction_type

      # Bank-specific (nullable for credit_card)
      t.decimal :balance, precision: 18, scale: 2
      t.string :tran_code
      t.string :tran_code_description

      # Credit-card-specific (nullable for bank)
      t.string :memo
      t.string :raw_category

      t.timestamps
    end

    add_index :cash_transactions, :source
    add_index :cash_transactions, :source_row_hash, unique: true
    add_index :cash_transactions, :transaction_date

    # Unified tag join table
    create_table :cash_transaction_tags do |t|
      t.references :cash_transaction, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :cash_transaction_tags, [ :cash_transaction_id, :tag_id ], unique: true
  end
end
