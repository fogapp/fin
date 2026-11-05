class AddBalanceCurrencyToAccountBalanceSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :account_balance_snapshots, :balance_currency, :string, default: "USD"
    add_column :account_balance_snapshots, :balance_usd,      :decimal, precision: 15, scale: 2
    AccountBalanceSnapshot.update_all("balance_usd = balance, balance_currency = 'USD'")
  end
end
