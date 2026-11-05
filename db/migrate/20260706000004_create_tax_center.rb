# Tax Center (docs/tax-center-design.md): the Tax Year as a first-class
# object, assembled from facts (ledger), records (user bookkeeping), and
# estimates (engine output).
#
# - accounts.tax_treatment powers contribution tracking (transfers into
#   retirement/HSA/529 accounts vs the year's limits) and wash-sale
#   permanent-disallowance warnings.
# - categories.charitable flags giving categories for the deductions section.
# - estimated_tax_payments: the per-year estimated-payment ledger (record).
# - tax_checklist_items: the document checklist, auto-seeded from ledger
#   data (W-2/1099/1098/3921/5498/charitable receipts) plus user rows.
# - tax_adjustments: arbitrary per-year line items (K-1s, rental income,
#   property tax, credits, extra payments, off-ledger contributions) so any
#   year's situation is representable without new code.
class CreateTaxCenter < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :tax_treatment, :string, null: false, default: "taxable"
    add_column :categories, :charitable, :boolean, null: false, default: false

    create_table :estimated_tax_payments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.integer :tax_year, null: false
      t.string :jurisdiction, null: false # federal | state
      t.date :paid_on, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :notes
      t.timestamps
      t.index %i[household_id tax_year]
    end
    add_foreign_key :estimated_tax_payments, :households, on_delete: :cascade

    create_table :tax_checklist_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.integer :tax_year, null: false
      t.string :kind, null: false # w2 1099_consolidated 1099_int 1099_r k1 1098 3921 3922 5498 property_tax charitable_receipt other
      t.string :source_label, null: false
      t.string :status, null: false, default: "expected" # expected | received | corrected | n_a
      t.boolean :auto_seeded, null: false, default: false
      t.uuid :reference_id # optional pointer (grant event, cash transaction)
      t.string :notes
      t.timestamps
      t.index %i[household_id tax_year kind source_label], unique: true,
              name: "index_tax_checklist_items_uniqueness"
    end
    add_foreign_key :tax_checklist_items, :households, on_delete: :cascade

    create_table :tax_adjustments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.integer :tax_year, null: false
      t.string :kind, null: false # income | deduction | credit | payment | contribution
      t.string :jurisdiction, null: false, default: "federal" # federal | state | both
      t.string :label, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :bucket # contribution kind only: 401k | ira | hsa | education
      t.string :notes
      t.timestamps
      t.index %i[household_id tax_year]
    end
    add_foreign_key :tax_adjustments, :households, on_delete: :cascade
  end
end
