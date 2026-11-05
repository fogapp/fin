class AddProjectedStateTaxToTaxProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :tax_profiles, :projected_state_tax, :decimal, precision: 14, scale: 2
  end
end
