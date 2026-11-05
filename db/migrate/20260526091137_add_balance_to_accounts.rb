class AddBalanceToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :balance, :decimal, precision: 15, scale: 2
  end
end
