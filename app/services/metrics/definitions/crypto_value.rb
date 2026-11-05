# typed: strict

module Metrics
  module Definitions
    # Total USD value of crypto account balances per day (latest snapshot per
    # account per day, summed — CryptoBalanceHistory).
    class CryptoValue < Definition
      key :crypto_value
      label "Crypto value"
      description "Total USD value of crypto holdings, tracked daily."
      unit Unit::Currency
      granularity Granularity::Day
      value_type ValueType::Level
      direction Direction::UpGood
      group Group::Investments

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        ::CryptoBalanceHistory.new.daily_totals
          .each_with_object({}) do |(date_str, value), out|
            date = Date.iso8601(date_str)
            out[date] = value.round(2) if date.between?(from, to)
          end
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        account_ids = ::Account
          .where.not(balance_currency: [ nil, "USD" ])
          .pluck(:id)
        return nil if account_ids.empty?

        ::AccountBalanceSnapshot.where(account_id: account_ids).minimum(:recorded_at)&.to_date
      end
    end
  end
end
