class CreateTransfersAndAddTransferIdToTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transfers, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Polymorphic "from" side (the outflow — money leaving an account)
      t.uuid   :from_transaction_id
      t.string :from_transaction_type  # "CashTransaction" | "InvestmentTransaction"

      # Polymorphic "to" side (the inflow — money arriving in an account)
      t.uuid   :to_transaction_id
      t.string :to_transaction_type    # "CashTransaction" | "InvestmentTransaction"

      t.decimal  :amount, precision: 18, scale: 2  # absolute value of the moved amount
      t.string   :note
      t.datetime :confirmed_at  # nil = auto-detected candidate; present = user-confirmed

      t.timestamps
    end

    add_index :transfers, [ :from_transaction_type, :from_transaction_id ],
              unique: true,
              where:  "from_transaction_id IS NOT NULL",
              name:   "index_transfers_on_from_transaction"

    add_index :transfers, [ :to_transaction_type, :to_transaction_id ],
              unique: true,
              where:  "to_transaction_id IS NOT NULL",
              name:   "index_transfers_on_to_transaction"

    # Denormalised FK on each transaction type for O(1) "is this a transfer?" checks
    add_column :cash_transactions,       :transfer_id, :uuid
    add_column :investment_transactions, :transfer_id, :uuid

    add_index :cash_transactions,       :transfer_id
    add_index :investment_transactions, :transfer_id

    add_foreign_key :cash_transactions,       :transfers, on_delete: :nullify
    add_foreign_key :investment_transactions, :transfers, on_delete: :nullify
  end
end
