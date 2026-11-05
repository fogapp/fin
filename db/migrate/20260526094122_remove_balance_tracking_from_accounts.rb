class RemoveBalanceTrackingFromAccounts < ActiveRecord::Migration[8.1]
  def change
    remove_column :accounts, :balance_tracking, :boolean
  end
end
