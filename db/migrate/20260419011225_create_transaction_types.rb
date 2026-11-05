class CreateTransactionTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :transaction_types do |t|
      t.string :code
      t.string :code_description
      t.string :category

      t.timestamps
    end
    add_index :transaction_types, :code, unique: true
  end
end
