# typed: strict

module Metrics
  # Computes a definition's series over [from, to] and upserts it into
  # metric_points for the current household — the write path shared by
  # Backfill (full history) and Refresh (trailing window). Idempotent:
  # rows are keyed on [household_id, metric_key, date].
  #
  # Must run inside Current.set(household:) — the definition's queries rely
  # on HouseholdScoped default scopes, and upsert_all bypasses the scoping
  # callbacks so household_id is injected into every row here explicitly.
  module Store
    extend T::Sig

    BATCH_SIZE = 500

    # Returns the number of points written.
    sig do
      params(definition_class: T.class_of(Definition), from: Date, to: Date,
             definition: T.nilable(Definition)).returns(Integer)
    end
    def self.write!(definition_class, from:, to:, definition: nil)
      household = Current.household!
      now = Time.current

      rows = (definition || definition_class.new).series(from: from, to: to).map do |date, value|
        {
          household_id: household.id,
          metric_key:   definition_class.key.to_s,
          date:         date,
          value:        value,
          computed_at:  now,
          created_at:   now,
          updated_at:   now
        }
      end

      rows.each_slice(BATCH_SIZE) do |slice|
        MetricPoint.upsert_all(slice, unique_by: %i[household_id metric_key date])
      end

      rows.size
    end
  end
end
