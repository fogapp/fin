class AddWatchedToSecurities < ActiveRecord::Migration[8.1]
  def change
    add_column :securities, :watched, :boolean, default: false, null: false
  end
end
