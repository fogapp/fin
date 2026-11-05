class CreateMerchantRules < ActiveRecord::Migration[8.1]
  def change
    create_table :merchant_rules do |t|
      t.references :merchant, null: false, foreign_key: true
      t.string :pattern, null: false
      t.integer :priority, null: false, default: 0
      t.timestamps
    end

    add_index :merchant_rules, [ :merchant_id, :priority ]
  end
end
