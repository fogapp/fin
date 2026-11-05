# typed: true

# Every read is scoped by household_id (HouseholdScoped default scope) and the
# hot paths filter/sort on a date column, so the single-column indexes force a
# filter+sort. Composites let Postgres serve the predicate and the ORDER BY.
class AddCompositePerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :cash_transactions, [ :household_id, :transaction_date ],
              name: "index_cash_transactions_on_household_and_date"
    # Cashflow drill-downs group by category/merchant within a date window.
    add_index :cash_transactions, [ :category_id, :transaction_date ],
              name: "index_cash_transactions_on_category_and_date"
    add_index :cash_transactions, [ :merchant_id, :transaction_date ],
              name: "index_cash_transactions_on_merchant_and_date"

    add_index :investment_transactions, [ :household_id, :trade_date ],
              name: "index_investment_transactions_on_household_and_date"

    add_index :position_snapshots, [ :household_id, :as_of_date ],
              name: "index_position_snapshots_on_household_and_date"
    # Positions::CurrentPositions species-filters with LIKE 'computed:%' /
    # 'plaid_holding:%'; a plain btree can't serve prefix LIKE, pattern ops can.
    add_index :position_snapshots, :source_row_hash,
              opclass: :text_pattern_ops,
              name: "index_position_snapshots_on_source_row_hash_pattern"
  end
end
