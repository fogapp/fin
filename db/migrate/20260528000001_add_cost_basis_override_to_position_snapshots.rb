class AddCostBasisOverrideToPositionSnapshots < ActiveRecord::Migration[7.2]
  def change
    add_column :position_snapshots, :cost_basis_override, :decimal, precision: 18, scale: 4
  end
end
