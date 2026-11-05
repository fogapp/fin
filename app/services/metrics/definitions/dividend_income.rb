# typed: strict

module Metrics
  module Definitions
    # Investment income received per month (dividends, interest — the
    # InvestmentTransaction.income categories), in USD.
    class DividendIncome < Definition
      key :dividend_income
      label "Dividend income"
      description "Dividends and interest received from investments each month."
      unit Unit::Currency
      granularity Granularity::Month
      value_type ValueType::Flow
      direction Direction::UpGood
      group Group::Investments

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        monthly_sum(
          ::InvestmentTransaction.income,
          from: from, to: to, column: :income_usd, date_column: :trade_date
        ).transform_values { |v| v.round(2) }
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        ::InvestmentTransaction.income.minimum(:trade_date)
      end

      sig { override.params(from: Date, to: Date).returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
      def breakdowns(from:, to:)
        rows = ::InvestmentTransaction.income
          .joins(:security)
          .where(trade_date: from..to)
          .group("COALESCE(securities.ticker, securities.name)")
          .sum(:income_usd)
          .sort_by { |_, sum| -sum.to_f }
          .first(8)
          .map { |name, sum| { label: name, value: sum.to_f.round(2), unit: "currency" } }
        return nil if rows.empty?

        [ { label: "Top payers", rows: rows } ]
      end
    end
  end
end
