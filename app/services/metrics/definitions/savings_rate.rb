# typed: strict

module Metrics
  module Definitions
    # Share of income kept each month: (income − spend) / income, in
    # percentage points. Undefined (NULL) for months with no income — a rate
    # against zero income is noise, not signal.
    class SavingsRate < Definition
      key :savings_rate
      label "Savings rate"
      description "Percentage of monthly income left after spending. Months without income are skipped."
      unit Unit::Percent
      granularity Granularity::Month
      value_type ValueType::Flow
      direction Direction::UpGood
      group Group::Cashflow

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        income = monthly_sum(::CashTransaction.income_like, from: from, to: to)
        spend  = monthly_sum(::CashTransaction.spend_like,  from: from, to: to, negate: true)

        income.to_h do |month, inc|
          value = inc.positive? ? (((inc - spend[month].to_f) / inc) * 100).round(2) : nil
          [ month, value ]
        end
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        ::CashTransaction.income_like.minimum(:transaction_date)
      end
    end
  end
end
