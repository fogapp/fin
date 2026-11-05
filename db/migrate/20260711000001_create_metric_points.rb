# Metric points: the precomputed store behind the Stats system. One row per
# (household, metric, period). Metric definitions live in code
# (app/services/metrics/definitions); this table only holds computed values.
#
# - metric_key identifies a Metrics::Definition (e.g. "cc_transaction_count")
# - date is the period start: first of month for monthly metrics, the day
#   itself for daily (level) metrics — same first-of-month keying as
#   budget_lines.month
# - value is nullable: a period where the metric is undefined (e.g. average
#   transaction size in a month with zero transactions) stores NULL rather
#   than a misleading 0
# - computed_at records when the value was last computed (staleness debugging)
#
# Rows are written exclusively via upsert_all keyed on
# [household_id, metric_key, date], so backfill and nightly refresh are
# idempotent. The unique index is also the read index — every query is
# household + key (+ date range), a pure left-prefix scan.
#
# Dimensioned sub-series (e.g. spend by category) are a v2 concern: add a
# dimension_key column defaulting '' and extend the unique index.
class CreateMetricPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :metric_points, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :household_id, null: false
      t.string :metric_key, null: false
      t.date :date, null: false # period start
      t.decimal :value, precision: 18, scale: 4
      t.datetime :computed_at, null: false
      t.timestamps
      t.index %i[household_id metric_key date], unique: true
    end
    add_foreign_key :metric_points, :households, on_delete: :cascade
  end
end
