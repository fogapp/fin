class SetBalanceTrackingDefaultTrue < ActiveRecord::Migration[8.1]
  def change
    change_column_default :accounts, :balance_tracking, from: false, to: true
    Account.update_all(balance_tracking: true)
  end
end
