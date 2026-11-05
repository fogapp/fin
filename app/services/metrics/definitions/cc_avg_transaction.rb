# typed: strict

module Metrics
  module Definitions
    # Average credit-card charge size: cc charge volume ÷ cc charge count,
    # over the card side of spend_like (so autopayments, which card imports
    # type as Returns, are excluded by their transfer link). The dashboard's
    # "Avg Txn" (dashboard.rb compact_stats) uses the same scope.
    class CcAvgTransaction < Definition
      key :cc_avg_transaction
      label "Average card transaction"
      description "Average size of a credit-card charge each month (charge volume ÷ charge count, returns included)."
      unit Unit::Currency
      granularity Granularity::Month
      value_type ValueType::Flow
      direction Direction::Neutral
      group Group::Cashflow
      drill route: "/transactions", params: { source: "credit_card" }

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        # Card sales are stored negative, returns positive; the negated net
        # sum is "money out through the card" for the month.
        sums   = monthly_sum(base_scope, from: from, to: to, negate: true)
        counts = monthly_count(base_scope, from: from, to: to)

        sums.to_h do |month, sum|
          count = counts[month].to_i
          [ month, count.positive? ? (sum / count).round(2) : nil ]
        end
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        base_scope.minimum(:transaction_date)
      end

      private

      sig { returns(T.untyped) }
      def base_scope
        ::CashTransaction.spend_like.source_credit_card
      end
    end
  end
end
