class CreateMerchants < ActiveRecord::Migration[8.1]
  def change
    create_table :merchants do |t|
      t.string :name, null: false
      t.timestamps
    end

    add_index :merchants, :name, unique: true
  end
end
