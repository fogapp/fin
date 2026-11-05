class AddNotesToMerchants < ActiveRecord::Migration[8.1]
  def change
    add_column :merchants, :notes, :text
  end
end
