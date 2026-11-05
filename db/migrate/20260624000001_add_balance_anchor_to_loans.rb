class AddBalanceAnchorToLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :loans, :balance_anchor_amount, :decimal, precision: 15, scale: 2
    add_column :loans, :balance_anchor_date, :date
  end
end
