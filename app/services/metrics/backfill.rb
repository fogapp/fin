# typed: strict

module Metrics
  # Recomputes the full stored series for one metric definition in the
  # current household. Idempotent: rows are written via upsert_all keyed on
  # [household_id, metric_key, date]. reset: true clears existing points
  # first — needed when a formula change makes previously stored periods
  # disappear (e.g. a month that no longer qualifies). Must run inside
  # Current.set(household:), like Store.
  class Backfill
    extend T::Sig

    MAX_HISTORY_YEARS = 10

    sig { params(definition_class: T.class_of(Definition), reset: T::Boolean).returns(Integer) }
    def call(definition_class, reset: false)
      definition = definition_class.new

      from = definition.earliest_date
      return 0 if from.nil?

      from = [ from, MAX_HISTORY_YEARS.years.ago.to_date ].max
      from = from.beginning_of_month if definition_class.granularity == Metrics::Granularity::Month

      MetricPoint.for_key(definition_class.key).delete_all if reset

      Store.write!(definition_class, from: from, to: Date.current, definition: definition)
    end
  end
end
