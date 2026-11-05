# typed: strict

module Recurring
  # The trailing timeline slice per series — up to the SETTLED_LIMIT most
  # recent settled occurrences plus the next pending one — fetched with
  # window functions instead of eager-loading every series' full history.
  # household_id rides along in the subselects so HouseholdScoped's default
  # scope stays valid on the outer query.
  class TimelineQuery
    extend T::Sig

    SETTLED_LIMIT = 10
    PENDING_LIMIT = 1

    sig { params(series_ids: T::Array[T.untyped]).returns(T::Hash[T.untyped, T::Array[RecurringOccurrence]]) }
    def self.call(series_ids)
      new(series_ids).call
    end

    sig { params(series_ids: T::Array[T.untyped]).void }
    def initialize(series_ids)
      @series_ids = T.let(series_ids, T::Array[T.untyped])
    end

    sig { returns(T::Hash[T.untyped, T::Array[RecurringOccurrence]]) }
    def call
      return {} if @series_ids.empty?

      scope = RecurringOccurrence.where(recurring_series_id: @series_ids)
      settled = scope.where.not(status: RecurringOccurrence::PENDING_STATUSES).select(
        "recurring_occurrences.*",
        "ROW_NUMBER() OVER (PARTITION BY recurring_series_id ORDER BY expected_date DESC, id DESC) AS timeline_rank"
      )
      pending = scope.where(status: RecurringOccurrence::PENDING_STATUSES).select(
        "recurring_occurrences.*",
        "ROW_NUMBER() OVER (PARTITION BY recurring_series_id ORDER BY expected_date ASC, id ASC) AS timeline_rank"
      )

      rows = RecurringOccurrence.from(settled, :recurring_occurrences).where("timeline_rank <= #{SETTLED_LIMIT}").to_a +
             RecurringOccurrence.from(pending, :recurring_occurrences).where("timeline_rank <= #{PENDING_LIMIT}").to_a
      rows.group_by(&:recurring_series_id)
    end
  end
end
