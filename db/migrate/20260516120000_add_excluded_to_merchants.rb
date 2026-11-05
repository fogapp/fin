class AddExcludedToMerchants < ActiveRecord::Migration[8.0]
  def change
    add_column :merchants, :excluded, :boolean, null: false, default: false
    add_index  :merchants, :excluded
  end
end
