class CreateBankTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_transactions do |t|
      t.date       :transaction_date, null: false
      t.date       :post_date
      t.string     :description
      t.string     :transaction_type
      t.decimal    :amount, precision: 18, scale: 2, null: false
      t.decimal    :balance, precision: 18, scale: 2
      t.string     :tran_code
      t.string     :tran_code_description
      t.references :account,  foreign_key: true, null: true
      t.references :merchant, foreign_key: true, null: true
      t.references :category, foreign_key: true, null: true
      t.string     :source_row_hash, null: false
      t.timestamps
    end

    add_index :bank_transactions, :source_row_hash, unique: true
    add_index :bank_transactions, :transaction_date

    create_table :bank_transaction_tags do |t|
      t.references :bank_transaction, null: false, foreign_key: true
      t.references :tag,              null: false, foreign_key: true
      t.timestamps
    end

    add_index :bank_transaction_tags, [ :bank_transaction_id, :tag_id ], unique: true
  end
end
