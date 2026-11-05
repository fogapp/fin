class AddIncludeUnvestedEquityToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :include_unvested_equity, :boolean, default: false, null: false
  end
end
