class CreateLoans < ActiveRecord::Migration[8.1]
  def change
    create_table :loans, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :household, null: false, foreign_key: true, type: :uuid
      t.references :account, null: true, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :lender
      t.string :loan_type, null: false
      t.decimal :original_principal, precision: 15, scale: 2, null: false
      t.decimal :interest_rate, precision: 8, scale: 4, null: false
      t.integer :term_months, null: false
      t.date :start_date, null: false
      t.decimal :monthly_payment, precision: 15, scale: 2
      t.string :status, null: false, default: "active"
      t.text :notes
      t.timestamps
    end

    add_column :cash_transactions, :loan_id, :uuid
    add_foreign_key :cash_transactions, :loans
    add_index :cash_transactions, :loan_id
  end
end
