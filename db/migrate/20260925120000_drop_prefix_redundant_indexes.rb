# typed: true

# Each of these single-column indexes is the leading column of a composite
# index on the same table, so Postgres can already serve its lookups from
# the composite. Keeping both only costs writes — every imported or synced
# row updated two btrees where one would do.
class DropPrefixRedundantIndexes < ActiveRecord::Migration[8.1]
  def change
    # Covered by (account_id, transaction_date), (category_id, transaction_date),
    # (household_id, transaction_date), (merchant_id, transaction_date) and
    # (source, transaction_type).
    remove_index :cash_transactions, :account_id,   name: "index_cash_transactions_on_account_id"
    remove_index :cash_transactions, :category_id,  name: "index_cash_transactions_on_category_id"
    remove_index :cash_transactions, :household_id, name: "index_cash_transactions_on_household_id"
    remove_index :cash_transactions, :merchant_id,  name: "index_cash_transactions_on_merchant_id"
    remove_index :cash_transactions, :source,       name: "index_cash_transactions_on_source"

    # Covered by (account_id, recorded_at).
    remove_index :account_balance_snapshots, :account_id, name: "index_account_balance_snapshots_on_account_id"

    # Covered by (account_id, security_id, as_of_date), (as_of_date, security_id)
    # and (household_id, as_of_date).
    remove_index :position_snapshots, :account_id,   name: "index_position_snapshots_on_account_id"
    remove_index :position_snapshots, :as_of_date,   name: "index_position_snapshots_on_as_of_date"
    remove_index :position_snapshots, :household_id, name: "index_position_snapshots_on_household_id"
  end
end
