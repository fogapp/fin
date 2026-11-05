class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # cash_transactions: transaction_type is filtered constantly (sales, returns, payments)
    add_index :cash_transactions, :transaction_type

    # cash_transactions: source + transaction_type together is the most common filter pattern
    add_index :cash_transactions, [ :source, :transaction_type ],
              name: "index_cash_transactions_on_source_and_type"

    # position_snapshots: as_of_date + security_id composite supports
    # the GROUP BY security_id after WHERE as_of_date = ? pattern
    add_index :position_snapshots, [ :as_of_date, :security_id ],
              name: "index_position_snapshots_on_date_and_security"
  end
end
