class CreateBrokers < ActiveRecord::Migration[8.1]
  def change
    create_table :brokers do |t|
      t.string :name

      t.timestamps
    end
    add_index :brokers, :name, unique: true
  end
end
