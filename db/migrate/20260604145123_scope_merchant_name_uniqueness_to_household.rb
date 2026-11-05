class ScopeMerchantNameUniquenessToHousehold < ActiveRecord::Migration[8.1]
  def change
    remove_index :merchants, :name, name: "index_merchants_on_name"
    add_index :merchants, [ :household_id, :name ], unique: true, name: "index_merchants_on_household_id_and_name"
  end
end
