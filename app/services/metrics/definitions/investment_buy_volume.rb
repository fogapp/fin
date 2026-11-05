# typed: strict

module Metrics
  module Definitions
    # Money invested per month: USD volume of purchase transactions.
    class InvestmentBuyVolume < Definition
      key :investment_buy_volume
      label "Investment buys"
      description "Amount invested in securities each month."
      unit Unit::Currency
      granularity Granularity::Month
      value_type ValueType::Flow
      direction Direction::Neutral
      group Group::Investments

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        monthly_sum(
          ::InvestmentTransaction.purchases,
          from: from, to: to, column: :amount_usd, date_column: :trade_date
        ).transform_values { |v| v.round(2) }
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        ::InvestmentTransaction.purchases.minimum(:trade_date)
      end
    end
  end
end
