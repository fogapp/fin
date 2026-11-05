class AddAccountToCreditCardTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :credit_card_transactions, :account, foreign_key: true, null: true
  end
end
