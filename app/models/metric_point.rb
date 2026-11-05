# typed: true

# A single precomputed value of a metric for one period. See
# Metrics::Definition for where values come from and Metrics::Backfill /
# Metrics::Refresh for how rows get written.
#
# NOTE: rows are written via upsert_all, which bypasses validations and the
# HouseholdScoped auto-assignment callback — writers must put household_id
# into every row hash explicitly.
class MetricPoint < ApplicationRecord
  extend T::Sig

  include HouseholdScoped

  validates :metric_key, :date, :computed_at, presence: true

  scope :for_key,  ->(key) { where(metric_key: key.to_s) }
  scope :in_range, ->(range) { where(date: range) }
  scope :ordered,  -> { order(date: :asc) }
end
