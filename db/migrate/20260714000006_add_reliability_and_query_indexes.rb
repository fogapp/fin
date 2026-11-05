# typed: true

# Query-shape indexes from the 2026-07-14 perf/reliability audit:
#
#   - cash_transactions (account_id, transaction_date): per-account date
#     windows (transfer candidate scan, account drill-downs) only had the
#     single-column account_id index.
#   - workflow_run_steps.workflow_step_id: the FK is ON DELETE SET NULL and
#     Workflow#replace_steps! destroy_all made Postgres seq-scan run steps
#     on every workflow edit.
#   - activity_entries.occurred_at: PruneActivityJob's nightly retention
#     delete filters on occurred_at alone (unscoped), which only had the
#     (household_id, occurred_at) composite.
#   - account_balance_snapshots (account_id, source, recorded_at):
#     AccountBalanceSnapshot.record looks up "today's row" per (account,
#     source, Time.zone day window) on every sync. Deliberately NON-unique:
#     .record dedups by Time.zone day (a moving, DST-aware window), which an
#     expression index on date(recorded_at) could not match — and historical
#     duplicates exist. daily_series tolerates stragglers via DISTINCT ON.
#   - pg_trgm GIN on cash_transactions.description: the transaction search
#     path (Api::Render::CashTransaction) filters with ILIKE '%term%', which
#     a btree can never serve; a trigram GIN index can.
#
# Checked and already covered (no-ops here): workflow_monitor_states has a
# unique (workflow_id, subject_type, subject_id) index; recurring_occurrences
# has a unique (recurring_series_id, expected_date) index.
class AddReliabilityAndQueryIndexes < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    add_index :cash_transactions, [ :account_id, :transaction_date ],
              name: "index_cash_transactions_on_account_and_date"

    add_index :workflow_run_steps, :workflow_step_id

    add_index :activity_entries, :occurred_at

    add_index :account_balance_snapshots, [ :account_id, :source, :recorded_at ],
              name: "index_balance_snapshots_on_account_source_recorded_at"

    add_index :cash_transactions, :description,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_cash_transactions_on_description_trgm"
  end
end
