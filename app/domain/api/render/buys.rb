# typed: strict

module Api
  module Render
    class Buys < Api::Render::Base
      extend T::Sig

      include Concerns::SerializesInvestmentTransaction

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def index
        from, to    = date_param(:from), date_param(:to)
        ytd_from    = Date.current.beginning_of_year
        scope       = InvestmentTransaction.purchases
        # Charts, lists, and the period stats follow the requested window;
        # all-time and YTD totals don't. The period stats fall back to the
        # trailing 12 months when no window is given ("All").
        windowed    = in_window(scope, from, to)
        period      = in_window(scope, from || 11.months.ago.beginning_of_month.to_date, to)

        total_cost  = scope.sum("amount_usd").to_f
        count       = scope.count

        {
          totals: {
            all_time:   total_cost,
            ytd:        scope.where(trade_date: ytd_from..).sum("amount_usd").to_f,
            last_12mo:  period.sum("amount_usd").to_f,
            count:      count,
            count_12mo: period.count,
            avg:        count.zero? ? 0.0 : (total_cost / count).round(2)
          },
          monthly_volume:      monthly_series_for(windowed, "amount_usd"),
          top_securities:      top_securities_for(windowed, "SUM(amount_usd)"),
          by_account:          by_account_for(windowed, "SUM(amount_usd)"),
          cumulative_invested: cumulative_series_for(in_window(scope, nil, to), "amount_usd", from: from),
          transactions:        windowed_for(windowed, params)
        }
      end
    end
  end
end
