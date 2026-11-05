# typed: strict

module Metrics
  module Definitions
    # Income minus spend per month (both per the shared income_like /
    # spend_like definitions). Positive = saved money that month.
    class NetCashflow < Definition
      key :net_cashflow
      label "Net cashflow"
      description "Income minus spending each month. Positive months add to savings."
      unit Unit::Currency
      granularity Granularity::Month
      value_type ValueType::Flow
      direction Direction::UpGood
      group Group::Cashflow

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        income = monthly_sum(::CashTransaction.income_like, from: from, to: to)
        spend  = monthly_sum(::CashTransaction.spend_like,  from: from, to: to, negate: true)

        income.to_h { |month, inc| [ month, (inc - spend[month].to_f).round(2) ] }
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        [
          ::CashTransaction.income_like.minimum(:transaction_date),
          ::CashTransaction.spend_like.minimum(:transaction_date)
        ].compact.min
      end
    end
  end
end
