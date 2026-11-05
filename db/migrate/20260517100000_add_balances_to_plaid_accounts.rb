class AddBalancesToPlaidAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :plaid_accounts, :balance_current,      :decimal, precision: 18, scale: 4
    add_column :plaid_accounts, :balance_available,    :decimal, precision: 18, scale: 4
    add_column :plaid_accounts, :balance_limit,        :decimal, precision: 18, scale: 4
    add_column :plaid_accounts, :balance_currency,     :string
    add_column :plaid_accounts, :balance_updated_at,   :datetime
  end
end
