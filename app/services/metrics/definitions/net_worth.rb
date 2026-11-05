# typed: strict

module Metrics
  module Definitions
    # Household net worth per day, sourced from NetWorthHistory (balance
    # snapshots + portfolio reconstruction + loan amortization). Not
    # reconstructible from transactions alone, so this wraps the service.
    #
    # NetWorthHistory samples weekly beyond ~400 days, so points older than
    # that are weekly-spaced — acceptable for a level series (each point is a
    # valuation, not a sum).
    class NetWorth < Definition
      key :net_worth
      label "Net worth"
      description "Total assets minus liabilities, tracked daily."
      unit Unit::Currency
      granularity Granularity::Day
      value_type ValueType::Level
      direction Direction::UpGood
      group Group::NetWorth

      sig { override.params(from: Date, to: Date).returns(T::Hash[Date, T.untyped]) }
      def series(from:, to:)
        payload = ::NetWorthHistory.new(range: covering_range(from)).call
        payload[:series].each_with_object({}) do |row, out|
          date = Date.iso8601(row[:date])
          out[date] = row[:net].to_f.round(2) if date.between?(from, to)
        end
      end

      sig { override.returns(T.nilable(Date)) }
      def earliest_date
        [
          ::AccountBalanceSnapshot
            .joins(:account)
            .where(accounts: { household_id: Current.household!.id })
            .minimum(:recorded_at)&.to_date,
          ::PositionSnapshot.minimum(:as_of_date)
        ].compact.min
      end

      private

      # NetWorthHistory takes a named range; pick the smallest one covering
      # `from` (trailing refresh uses ~35 days → 3m; backfill → all).
      sig { params(from: Date).returns(::NetWorthHistory::RangeKey) }
      def covering_range(from)
        today = Date.current
        return ::NetWorthHistory::RangeKey::ThreeMonths if from >= today << 3
        return ::NetWorthHistory::RangeKey::Ytd if from >= today.beginning_of_year
        return ::NetWorthHistory::RangeKey::OneYear if from >= today - 1.year

        ::NetWorthHistory::RangeKey::All
      end
    end
  end
end
