# typed: strict

module Metrics
  module Definitions
    # Total income per month — the app-wide income_like definition (bank
    # deposits minus credit-card autopay noise and transfers).
    class MonthlyIncome < Definition
      key :monthly_income
      label "Monthly income"
      description "Total income deposited each month, excluding transfers and credit-card payments."
      unit Unit::Currency
      granularity Granularity::Month
      value_type ValueType::Flow
      direction Direction::UpGood
      group Group::Cashflow
      drill route: "/transactions", params: {}

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        monthly_sum(::CashTransaction.income_like, from: from, to: to)
          .transform_values { |v| v.round(2) }
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        ::CashTransaction.income_like.minimum(:transaction_date)
      end
    end
  end
end
