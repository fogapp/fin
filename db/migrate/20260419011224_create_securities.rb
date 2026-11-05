class CreateSecurities < ActiveRecord::Migration[8.1]
  def change
    create_table :securities do |t|
      t.string :cusip
      t.string :ticker
      t.string :security_type
      t.string :name

      t.timestamps
    end
    add_index :securities, :cusip, unique: true, where: "cusip IS NOT NULL"
    add_index :securities, :ticker
  end
end
