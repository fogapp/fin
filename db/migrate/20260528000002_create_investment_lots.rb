class CreateInvestmentLots < ActiveRecord::Migration[7.2]
  def change
    create_table :investment_lots, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.uuid :security_id,  null: false
      t.uuid :account_id
      t.date :acquired_date
      t.decimal :quantity,   precision: 18, scale: 6, null: false
      t.decimal :cost_basis, precision: 18, scale: 4, null: false
      t.string :notes
      t.timestamps

      t.index :household_id
      t.index :security_id
      t.index :account_id
    end

    add_foreign_key :investment_lots, :households, on_delete: :cascade
    add_foreign_key :investment_lots, :securities
    add_foreign_key :investment_lots, :accounts
  end
end
