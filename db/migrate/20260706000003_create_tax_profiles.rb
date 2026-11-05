# One editable tax profile per (household, tax_year) feeding the exercise
# planner (docs/exercise-planner-design.md): projected income, deduction
# posture, prior-year safe-harbor facts, and YTD withholding. v1 is
# user-entered; later prefillable from Fin data.
class CreateTaxProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :tax_profiles, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.integer :tax_year, null: false
      t.string :filing_status, null: false, default: "single" # single mfj
      t.string :state, null: false, default: "CA"
      t.decimal :projected_wages, precision: 14, scale: 2, null: false, default: 0
      t.decimal :other_ordinary_income, precision: 14, scale: 2, null: false, default: 0
      t.decimal :ltcg_qd_income, precision: 14, scale: 2, null: false, default: 0
      t.boolean :itemizing, null: false, default: false
      t.decimal :salt_paid, precision: 14, scale: 2, null: false, default: 0
      t.decimal :itemized_other, precision: 14, scale: 2, null: false, default: 0
      t.decimal :prior_year_total_tax, precision: 14, scale: 2
      t.decimal :prior_year_agi, precision: 14, scale: 2
      t.decimal :ytd_withholding_federal, precision: 14, scale: 2, null: false, default: 0
      t.decimal :ytd_withholding_state, precision: 14, scale: 2, null: false, default: 0
      t.decimal :amt_credit_carryforward_federal, precision: 14, scale: 2, null: false, default: 0
      t.decimal :amt_credit_carryforward_ca, precision: 14, scale: 2, null: false, default: 0
      t.timestamps
      t.index %i[household_id tax_year], unique: true
    end
    add_foreign_key :tax_profiles, :households, on_delete: :cascade
  end
end
