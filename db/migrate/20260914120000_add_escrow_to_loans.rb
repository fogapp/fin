class AddEscrowToLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :loans, :escrow_property_tax, :decimal, precision: 15, scale: 2
    add_column :loans, :escrow_insurance, :decimal, precision: 15, scale: 2
    add_column :loans, :escrow_other, :decimal, precision: 15, scale: 2
  end
end
