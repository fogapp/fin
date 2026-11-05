# typed: strict

module Api
  module Render
    class Sells < Api::Render::Base
      extend T::Sig

      include Concerns::SerializesInvestmentTransaction

      GL_SUM = "COALESCE(gl_short_usd, 0) + COALESCE(gl_long_usd, 0)"

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def index
        from, to       = date_param(:from), date_param(:to)
        ytd_from       = Date.current.beginning_of_year
        scope          = InvestmentTransaction.sales
        # Same windowing contract as Buys: charts/lists follow the window,
        # lifetime totals don't, period stats default to the trailing year.
        windowed       = in_window(scope, from, to)
        period         = in_window(scope, from || 11.months.ago.beginning_of_month.to_date, to)

        proceeds = scope.sum(:amount_usd).to_f
        count    = scope.count
        short_gl = scope.sum(:gl_short_usd).to_f
        long_gl  = scope.sum(:gl_long_usd).to_f

        {
          totals: {
            proceeds:       proceeds,
            proceeds_ytd:   scope.where(trade_date: ytd_from..).sum(:amount_usd).to_f,
            proceeds_12mo:  period.sum(:amount_usd).to_f,
            count:          count,
            count_12mo:     period.count,
            avg:            count.zero? ? 0.0 : (proceeds / count).round(2),
            realized_short: short_gl,
            realized_long:  long_gl,
            realized_net:   (short_gl + long_gl).round(2)
          },
          monthly_volume:    monthly_series_for(windowed, "amount_usd"),
          monthly_gl:        monthly_series_for(windowed, GL_SUM),
          top_securities:    top_securities_for(windowed, "SUM(amount_usd)"),
          by_account:        by_account_for(windowed, "SUM(amount_usd)"),
          cumulative_realized: cumulative_series_for(in_window(scope, nil, to), GL_SUM, from: from),
          transactions:      windowed_for(windowed, params)
        }
      end
    end
  end
end
