# typed: strict

module Recurring
  # Household-wide subscription totals for the index header and review
  # badge — always computed across every series regardless of the page's
  # status filter, so the header never needs a second request.
  class SeriesSummary
    extend T::Sig

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def self.call
      new.call
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def call
      # monthly_equivalent is cadence math (Ruby), so active series load;
      # the occurrence sums stay in SQL — they used to load every occurrence
      # row of the month just to add two columns.
      active = RecurringSeries.active.to_a
      monthly_total = active.sum(&:monthly_equivalent).round(2)
      month_range = Date.current.beginning_of_month..Date.current.end_of_month
      month_occurrences = RecurringOccurrence
        .joins(:recurring_series)
        .where(recurring_series: { status: RecurringSeries::Status::Active }, expected_date: month_range)

      {
        active_count: active.size,
        suggested_count: RecurringSeries.suggested.count,
        lapsed_count: RecurringSeries.lapsed.count,
        monthly_total: monthly_total,
        annual_total: (monthly_total * 12).round(2),
        month_paid: month_occurrences.paid_like.sum(:amount).to_f.round(2),
        month_remaining: month_occurrences.pending.sum(:expected_amount).to_f.round(2)
      }
    end
  end
end
