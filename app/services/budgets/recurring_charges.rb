# typed: strict

module Budgets
  # Recurring charges (subscriptions and bills) by category, for the budget
  # forecast and suggestions. A series has no category of its own, so it
  # takes the category of its most recent matched transaction; series that
  # never matched a categorized transaction are left out.
  class RecurringCharges
    extend T::Sig

    LIVE_STATUSES = T.let([ RecurringSeries::Status::Active, RecurringSeries::Status::Suggested ].freeze,
                          T::Array[RecurringSeries::Status])

    sig { params(month: Date).void }
    def initialize(month:)
      @month = T.let(month.beginning_of_month, Date)
      @series_categories = T.let(nil, T.nilable(T::Hash[String, String]))
    end

    # Expected charges still pending this month (upcoming or due, not yet
    # matched to a transaction), summed per category.
    sig { returns(T::Hash[String, Float]) }
    def pending_by_category
      rows = RecurringOccurrence.pending
        .joins(:recurring_series).where(recurring_series: { status: LIVE_STATUSES.map(&:serialize) })
        .where(expected_date: @month..@month.end_of_month)
        .pluck(:recurring_series_id, :expected_amount)
      sum_by_category(rows)
    end

    # Occurrences already paid this month, summed per category of the
    # matched transaction.
    sig { returns(T::Hash[String, Float]) }
    def paid_by_category
      RecurringOccurrence.paid_like
        .joins(:cash_transaction)
        .where(charged_date: @month..@month.end_of_month)
        .where.not(cash_transactions: { category_id: nil })
        .pluck("cash_transactions.category_id", :amount)
        .each_with_object(Hash.new(0.0)) { |(category_id, amount), out| out[category_id] += amount.to_f.abs }
    end

    # Monthly-equivalent cost of live series per category — a floor for a
    # category's suggested budget.
    sig { returns(T::Hash[String, Float]) }
    def monthly_by_category
      RecurringSeries.where(status: LIVE_STATUSES.map(&:serialize)).to_a
        .each_with_object(Hash.new(0.0)) do |series, out|
          category_id = series_categories[series.id]
          out[category_id] += series.monthly_equivalent.abs if category_id
        end
    end

    private

    sig { params(rows: T::Array[[ String, T.untyped ]]).returns(T::Hash[String, Float]) }
    def sum_by_category(rows)
      rows.each_with_object(Hash.new(0.0)) do |(series_id, amount), out|
        category_id = series_categories[series_id]
        out[category_id] += amount.to_f.abs if category_id && amount
      end
    end

    sig { returns(T::Hash[String, String]) }
    def series_categories
      @series_categories ||= RecurringOccurrence.paid_like
        .joins(:cash_transaction)
        .where.not(cash_transactions: { category_id: nil })
        .order(charged_date: :desc)
        .pluck(:recurring_series_id, "cash_transactions.category_id")
        .each_with_object({}) { |(series_id, category_id), out| out[series_id] ||= category_id }
    end
  end
end
