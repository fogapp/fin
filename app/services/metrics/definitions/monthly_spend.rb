# typed: strict

module Metrics
  module Definitions
    # Total spend per month — the app-wide spend_like definition (credit-card
    # sales/returns plus bank debits, minus autopay noise, transfers, and
    # excluded merchants), negated so spend reads positive.
    class MonthlySpend < Definition
      key :monthly_spend
      label "Monthly spend"
      description "Total spending each month across credit cards and bank accounts, excluding transfers and card payments."
      unit Unit::Currency
      granularity Granularity::Month
      value_type ValueType::Flow
      direction Direction::DownGood
      group Group::Cashflow
      drill route: "/transactions", params: {}

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        monthly_sum(::CashTransaction.spend_like, from: from, to: to, negate: true)
          .transform_values { |v| v.round(2) }
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        ::CashTransaction.spend_like.minimum(:transaction_date)
      end

      sig { override.params(from: Date, to: Date).returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
      def breakdowns(from:, to:)
        rows = ::CashTransaction.spend_like
          .joins(:category)
          .where(transaction_date: from..to)
          .group("categories.name")
          .sum(:amount)
          .map { |name, sum| [ name, -sum.to_f ] }
          .sort_by { |_, total| -total }
          .first(8)
          .map { |name, total| { label: name, value: total.round(2), unit: "currency" } }
        return nil if rows.empty?

        [ { label: "Top categories", rows: rows } ]
      end
    end
  end
end
