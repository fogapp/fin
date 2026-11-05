class AddBalanceTrackingToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :balance_tracking, :boolean, default: false, null: false
  end
end
