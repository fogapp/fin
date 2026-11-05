# typed: strict

module Api
  module Render
    class Dividends < Api::Render::Base
      extend T::Sig

      include Concerns::SerializesInvestmentTransaction

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def index
        from, to    = date_param(:from), date_param(:to)
        ytd_from    = Date.current.beginning_of_year
        scope       = InvestmentTransaction.dividends
        # Same windowing contract as Buys.
        windowed    = in_window(scope, from, to)
        period      = in_window(scope, from || 11.months.ago.beginning_of_month.to_date, to)

        lifetime = scope.sum(:amount_usd).to_f
        count    = scope.count

        {
          totals: {
            lifetime:   lifetime,
            ytd:        scope.where(trade_date: ytd_from..).sum(:amount_usd).to_f,
            last_12mo:  period.sum(:amount_usd).to_f,
            count:      count,
            count_12mo: period.count,
            avg:        count.zero? ? 0.0 : (lifetime / count).round(2)
          },
          monthly_dividends:    monthly_series_for(windowed, "amount_usd"),
          top_securities:       top_securities_for(windowed, "SUM(amount_usd)"),
          by_account:           by_account_for(windowed, "SUM(amount_usd)"),
          cumulative_dividends: cumulative_series_for(in_window(scope, nil, to), "amount_usd", from: from),
          transactions:         windowed_for(windowed, params)
        }
      end
    end
  end
end
