class CreateRecurringPatterns < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_patterns do |t|
      t.references :merchant, foreign_key: true
      t.string  :description
      t.string  :interval_type,     null: false
      t.float   :interval_days,     null: false
      t.decimal :average_amount,    precision: 10, scale: 2, null: false
      t.date    :last_charge_date,  null: false
      t.date    :next_expected_date
      t.integer :transaction_count, null: false, default: 0
      t.float   :confidence,        null: false, default: 0.0
      t.boolean :active,            null: false, default: true

      t.timestamps
    end

    add_index :recurring_patterns, :active
    add_index :recurring_patterns, [ :merchant_id, :description ], unique: true, name: "index_recurring_patterns_on_merchant_or_description"
  end
end
