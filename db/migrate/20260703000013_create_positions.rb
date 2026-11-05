# Phase 3 of docs/instruments_platform_design.md: ledger-derived positions.
# One row per (account, instrument), rebuilt idempotently from the
# transaction ledger — the source of truth the custodian observations
# (position_snapshots) reconcile against.
class CreatePositions < ActiveRecord::Migration[8.1]
  def change
    create_table :positions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.uuid :account_id, null: false
      t.uuid :security_id, null: false
      t.decimal :quantity, precision: 24, scale: 8, null: false, default: 0
      t.decimal :cost_basis, precision: 20, scale: 4
      t.date :first_acquired_on
      t.datetime :ledger_updated_at
      t.timestamps
      t.index %i[account_id security_id], unique: true
      t.index %i[household_id security_id]
    end
    add_foreign_key :positions, :households, on_delete: :cascade
    add_foreign_key :positions, :accounts, on_delete: :cascade
    add_foreign_key :positions, :securities, on_delete: :cascade
  end
end
