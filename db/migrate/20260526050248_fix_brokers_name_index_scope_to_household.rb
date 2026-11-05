class FixBrokersNameIndexScopeToHousehold < ActiveRecord::Migration[8.1]
  def change
    remove_index :brokers, :name, name: "index_brokers_on_name"
    add_index :brokers, [ :household_id, :name ], unique: true, name: "index_brokers_on_household_id_and_name"
  end
end
