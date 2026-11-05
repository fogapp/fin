class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.references :broker, null: false, foreign_key: true
      t.string :name, null: false
      t.string :account_number, null: false
      t.string :account_type

      t.timestamps
    end
    add_index :accounts, [ :broker_id, :account_number ], unique: true
  end
end
