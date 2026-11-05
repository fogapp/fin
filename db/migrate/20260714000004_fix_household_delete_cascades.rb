# typed: true

# Household deletion relies on DB-level cascades (households_controller
# deletes via delete_all and lets ON DELETE CASCADE fan out), but several
# FKs were NO ACTION and blocked the delete once real data existed:
#
#   - account_balance_snapshots has no household_id column, so nothing
#     deleted its rows when accounts cascaded away → FK violation. Snapshots
#     are owned by their account → CASCADE.
#   - loans → households had no cascade at all → FK violation. Loans are
#     household-owned → CASCADE.
#   - cash_transaction_tags has no household_id column either; its rows
#     reference cash_transactions/tags (both of which cascade away with the
#     household) → FK violation. Join rows are owned by both sides → CASCADE.
#
# The remaining NO ACTION FKs whose two sides both cascade from households
# (cash_transactions → accounts/categories/merchants/loans, csv_imports →
# accounts, recurring_series → accounts/merchants, loans → accounts/
# merchants, ...) do not block household deletion — Postgres checks NO
# ACTION constraints at end of statement, by which point both sides are
# gone. But the optional-link ones below DO block deleting a single account
# or merchant on its own, so they become SET NULL (the columns are nullable
# and the associations are optional metadata, not ownership).
class FixHouseholdDeleteCascades < ActiveRecord::Migration[8.1]
  def change
    # Owned data: cascade.
    remove_foreign_key :account_balance_snapshots, :accounts
    add_foreign_key :account_balance_snapshots, :accounts, on_delete: :cascade

    remove_foreign_key :loans, :households
    add_foreign_key :loans, :households, on_delete: :cascade

    remove_foreign_key :cash_transaction_tags, :cash_transactions
    add_foreign_key :cash_transaction_tags, :cash_transactions, on_delete: :cascade

    remove_foreign_key :cash_transaction_tags, :tags
    add_foreign_key :cash_transaction_tags, :tags, on_delete: :cascade

    # Optional links: nullify so deleting the target alone can't be blocked.
    remove_foreign_key :loans, :accounts
    add_foreign_key :loans, :accounts, on_delete: :nullify

    remove_foreign_key :loans, :merchants
    add_foreign_key :loans, :merchants, on_delete: :nullify

    remove_foreign_key :csv_imports, column: :target_account_id
    add_foreign_key :csv_imports, :accounts, column: :target_account_id, on_delete: :nullify

    remove_foreign_key :recurring_series, :accounts
    add_foreign_key :recurring_series, :accounts, on_delete: :nullify

    remove_foreign_key :recurring_series, :merchants
    add_foreign_key :recurring_series, :merchants, on_delete: :nullify
  end
end
