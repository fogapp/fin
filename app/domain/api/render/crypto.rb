# typed: strict

module Api
  module Render
    class Crypto < Api::Render::Base
      extend T::Sig

      include Concerns::SerializesInvestmentTransaction

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def index
        ytd_from = Date.current.beginning_of_year

        txn_scope = InvestmentTransaction
          .joins(:security)
          .where(securities: { security_type: ::Security::CRYPTO_TYPE })

        buys_scope = txn_scope.purchases
        total_invested = buys_scope.sum("ABS(amount_usd)").to_f
        buy_count      = buys_scope.count

        # Activity charts and lists follow the requested window; the summary
        # and current positions are point-in-time and don't.
        from, to     = date_param(:from), date_param(:to)
        window_buys  = in_window(buys_scope, from, to)
        window_txns  = in_window(txn_scope, from, to)

        # Current positions from PositionSnapshot — one row per security
        # (grouping by price splits a security into duplicate rows whenever
        # two snapshots disagree on price).
        positions = PositionSnapshot
          .where(asset_class: "Crypto")
          .joins(:security)
          .group(
            "position_snapshots.security_id",
            "securities.ticker",
            "securities.name",
            "securities.cusip"
          )
          .order(Arel.sql("SUM(position_snapshots.market_value) DESC NULLS LAST"))
          .pluck(
            "position_snapshots.security_id",
            "securities.ticker",
            "securities.name",
            "securities.cusip",
            Arel.sql("MAX(position_snapshots.price)"),
            Arel.sql("SUM(position_snapshots.quantity)"),
            Arel.sql("SUM(position_snapshots.market_value)"),
            Arel.sql("SUM(position_snapshots.cost_basis)"),
            Arel.sql("SUM(position_snapshots.unrealized_gain_loss)")
          )
          .map do |id, ticker, name, cusip, price, qty, mval, cost, gl|
            cost_f = cost.to_f
            gl_f   = gl.to_f
            {
              id:            id,
              security_id:   id,
              ticker:        ticker,
              name:          name,
              cusip:         cusip,
              label:         nil,
              quantity:      qty.to_f,
              price:         price.to_f,
              market_value:  mval.to_f.round(2),
              cost_basis:    cost_f.round(2),
              unrealized_gl: gl_f.round(2),
              unrealized_gl_pct: cost_f > 0 ? ((gl_f / cost_f) * 100).round(2) : 0.0
            }
          end

        crypto_labels = ::SecurityLabel.by_security(positions.map { |p| p[:security_id] })
        positions.each { |p| p[:label] = crypto_labels[p[:security_id]] } if crypto_labels.any?

        total_value    = positions.sum { |p| p[:market_value] }
        total_cost     = positions.sum { |p| p[:cost_basis] }
        unrealized_gl  = positions.sum { |p| p[:unrealized_gl] }

        # Balance history from crypto accounts
        balance_history = ::CryptoBalanceHistory.new.daily_totals
          .select { |date, _| (from.nil? || date >= from.iso8601) && (to.nil? || date <= to.iso8601) }
          .transform_values { |v| v.round(2) }

        {
          summary: {
            total_value:    total_value.round(2),
            total_cost:     total_cost.round(2),
            unrealized_gl:  unrealized_gl.round(2),
            total_invested: total_invested.round(2),
            buy_count:      buy_count,
            ytd_invested:   buys_scope.where(trade_date: ytd_from..).sum("ABS(amount_usd)").to_f.round(2)
          },
          positions:        positions,
          balance_history:  balance_history,
          monthly_volume:      monthly_series_for(window_buys, "ABS(amount_usd)"),
          cumulative_invested: cumulative_series_for(in_window(buys_scope, nil, to), "ABS(amount_usd)", from: from),
          top_assets:          top_securities_for(window_buys, "SUM(ABS(amount_usd))"),
          by_account:          by_account_for(window_txns, "SUM(ABS(amount_usd))"),
          recent:              recent_for(window_txns)
        }
      end
    end
  end
end
