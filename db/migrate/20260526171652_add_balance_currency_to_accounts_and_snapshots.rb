class AddBalanceCurrencyToAccountsAndSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :balance_currency, :string, default: "USD"
    add_column :accounts, :balance_usd,      :decimal, precision: 15, scale: 2
    Account.where.not(balance: nil).update_all("balance_usd = balance, balance_currency = 'USD'")
  end
end
