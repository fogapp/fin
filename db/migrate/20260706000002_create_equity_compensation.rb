# Equity compensation (docs/feature-explorations.md §5): manual-entry Carta
# replacement — companies with an FMV history, grants with flat or custom
# vesting schedules, and grant events (exercise/settlement/sale/cancellation).
# Vested quantities are always derived (Equity::VestingCalculator), never stored.
class CreateEquityCompensation < ActiveRecord::Migration[8.1]
  def change
    create_table :equity_companies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.string :name, null: false
      t.boolean :public_company, null: false, default: false
      t.uuid :security_id # linked market instrument for public companies
      t.boolean :c_corp, null: false, default: true
      t.boolean :qsbs_candidate, null: false, default: false
      t.decimal :preferred_price, precision: 18, scale: 6
      t.string :notes
      t.timestamps
      t.index :household_id
    end
    add_foreign_key :equity_companies, :households, on_delete: :cascade
    add_foreign_key :equity_companies, :securities, on_delete: :nullify

    create_table :equity_fmv_entries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :equity_company_id, null: false
      t.uuid :household_id, null: false
      t.decimal :price_per_share, precision: 18, scale: 6, null: false
      t.date :effective_date, null: false
      t.string :source, null: false, default: "409a"
      t.timestamps
      t.index %i[equity_company_id effective_date], unique: true
      t.index :household_id
    end
    add_foreign_key :equity_fmv_entries, :equity_companies, on_delete: :cascade
    add_foreign_key :equity_fmv_entries, :households, on_delete: :cascade

    create_table :equity_grants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :equity_company_id, null: false
      t.uuid :household_id, null: false
      t.string :label
      t.string :grant_type, null: false # iso nso rsu rsa
      t.date :grant_date, null: false
      t.date :vesting_commencement_date # defaults to grant_date at the model layer
      t.decimal :quantity, precision: 18, scale: 4, null: false
      t.decimal :strike_price, precision: 18, scale: 6 # options only
      t.boolean :early_exercisable, null: false, default: false
      t.boolean :double_trigger, null: false, default: false
      t.date :expiration_date
      t.integer :pte_window_days
      t.string :vesting_interval # monthly quarterly annual; nil with custom_tranches
      t.integer :vesting_occurrences
      t.integer :cliff_installments, null: false, default: 0
      t.jsonb :custom_tranches # [{date:, quantity:}, ...] escape hatch for irregular curves
      t.string :notes
      t.timestamps
      t.index :equity_company_id
      t.index :household_id
    end
    add_foreign_key :equity_grants, :equity_companies, on_delete: :cascade
    add_foreign_key :equity_grants, :households, on_delete: :cascade

    create_table :equity_grant_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :equity_grant_id, null: false
      t.uuid :household_id, null: false
      t.string :kind, null: false # exercise settlement sale cancellation
      t.date :occurred_on, null: false
      t.decimal :quantity, precision: 18, scale: 4, null: false
      t.decimal :share_price, precision: 18, scale: 6 # FMV at exercise/settlement, or sale price
      t.string :method # cash cashless sell_to_cover net_settlement (exercise/settlement)
      t.string :buyer_type # company_tender third_party (sales)
      t.boolean :election_83b, null: false, default: false
      t.date :election_83b_date
      t.decimal :shares_withheld, precision: 18, scale: 4
      t.string :notes
      t.timestamps
      t.index :equity_grant_id
      t.index :household_id
    end
    add_foreign_key :equity_grant_events, :equity_grants, on_delete: :cascade
    add_foreign_key :equity_grant_events, :households, on_delete: :cascade
  end
end
