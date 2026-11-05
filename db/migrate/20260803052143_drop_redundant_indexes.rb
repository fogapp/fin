# Drops six indexes that earn nothing, chosen from production
# pg_stat_user_indexes counts rather than from schema shape alone.
#
# The big one is market_prices.security_id: 24 MB on a table carrying 2.1M
# inserts and 1.3M updates, and strictly a prefix of [security_id, date].
# EXPLAIN ANALYZE inside a rolled-back transaction on production confirmed
# that both query shapes the app actually issues — the latest-close lookup
# (MarketData::PriceSeries) and the per-security max(date) roll-up (system
# health) — produce identical plans with the index dropped. The planner
# already prefers the composite for both; the recorded idx_scan count
# belongs to query shapes the code no longer issues.
#
# The next four are prefix-redundant *and* show zero scans in production —
# nothing has read them since the counters were last reset.
# investment_transactions.executing_dealer isn't redundant but is never
# queried at all: the column is only ever written (CSV import, backup
# export/restore).
#
# Deliberately NOT dropped: the other 15 prefix-redundant indexes a schema
# scan turns up. They sit on tables that are small in production
# (cash_transactions 1,093 rows, position_snapshots 612,
# investment_transactions 4,522) where the entire index set is under a
# megabyte, so write amplification is unmeasurable — and several are the
# planner's actual choice (cash_transactions.category_id has 5,072 scans,
# merchant_id 2,613, account_id 1,687). Dropping those would trade live read
# paths for no measurable write gain. Also kept: cash_transactions.memo_trgm,
# which shows zero scans but backs the memo column in sitewide search.
class DropRedundantIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # [table, columns, index name]
  DROPS = [
    [ :market_prices,           [ :security_id ],         "index_market_prices_on_security_id" ],
    [ :cash_transaction_tags,   [ :cash_transaction_id ], "index_cash_transaction_tags_on_cash_transaction_id" ],
    [ :merchant_rules,          [ :merchant_id ],         "index_merchant_rules_on_merchant_id" ],
    [ :household_memberships,   [ :user_id ],             "index_household_memberships_on_user_id" ],
    [ :real_estate_properties,  [ :household_id ],        "index_real_estate_properties_on_household_id" ],
    [ :investment_transactions, [ :executing_dealer ],    "index_investment_transactions_on_executing_dealer" ]
  ].freeze

  def up
    DROPS.each do |table, _columns, name|
      remove_index table, name: name, algorithm: :concurrently, if_exists: true
    end
  end

  def down
    DROPS.each do |table, columns, name|
      add_index table, columns, name: name, algorithm: :concurrently, if_not_exists: true
    end
  end
end
