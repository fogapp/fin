# typed: strict

module Metrics
  module Definitions
    # Matches the dashboard "CC Txns" scope (dashboard.rb compact_stats):
    # the card side of spend_like — purchases and returns, but not
    # autopayments (card imports type them as Returns; their transfer link
    # excludes them).
    class CcTransactionCount < Definition
      key :cc_transaction_count
      label "Credit-card transactions"
      description "Number of credit-card purchases and returns each month. Card payments are excluded."
      unit Unit::Count
      granularity Granularity::Month
      value_type ValueType::Flow
      direction Direction::Neutral
      group Group::Cashflow
      drill route: "/transactions", params: { source: "credit_card" }

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        monthly_count(base_scope, from: from, to: to)
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        base_scope.minimum(:transaction_date)
      end

      sig { override.params(from: Date, to: Date).returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
      def breakdowns(from:, to:)
        rows = base_scope
          .joins(:merchant)
          .where(transaction_date: from..to)
          .group("merchants.name")
          .count
          .sort_by { |_, count| -count }
          .first(8)
          .map { |name, count| { label: name, value: count, unit: "count" } }
        return nil if rows.empty?

        [ { label: "Top merchants", rows: rows } ]
      end

      private

      sig { returns(T.untyped) }
      def base_scope
        ::CashTransaction.spend_like.source_credit_card
      end
    end
  end
end
