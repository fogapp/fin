# typed: strict

module Api
  module Render
    class Portfolio < Api::Render::Base
      extend T::Sig

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def index
        current     = ::Positions::CurrentPositions.new
        as_of       = current.as_of_date
        all_current = current.relation

        total_value, total_income = all_current.pick(
          Arel.sql("SUM(market_value)"),
          Arel.sql("SUM(est_annual_income)")
        ).map { |v| v.to_f }

        by_asset_class = all_current
          .group(Arel.sql("COALESCE(asset_class, 'Other')"))
          .sum(:market_value)
          .transform_keys(&:to_s)
          .transform_values { |v| v.to_f.round(2) }
          .sort_by { |_, v| -v }
          .to_h

        history = merged_portfolio_history

        # One row per security. Imported and computed snapshots for the same
        # security rarely share a price, so grouping by price (as this used
        # to) emitted duplicate rows whose lot-based cost basis was then
        # double-counted into the totals.
        consolidated = all_current
          .joins(:security)
          .group(
            "position_snapshots.security_id",
            "securities.ticker",
            "securities.name",
            "securities.cusip",
            "position_snapshots.asset_class"
          )
          .order(Arel.sql("SUM(position_snapshots.market_value) DESC NULLS LAST"))
          .pluck(
            "position_snapshots.security_id",
            "securities.ticker",
            "securities.name",
            "securities.cusip",
            "position_snapshots.asset_class",
            Arel.sql("MAX(position_snapshots.price)"),
            Arel.sql("MAX(position_snapshots.dividend_yield)"),
            Arel.sql("SUM(position_snapshots.quantity)"),
            Arel.sql("SUM(position_snapshots.market_value)"),
            Arel.sql("SUM(COALESCE(position_snapshots.cost_basis_override, position_snapshots.cost_basis))"),
            Arel.sql("SUM(position_snapshots.unrealized_gain_loss)"),
            Arel.sql("SUM(position_snapshots.est_annual_income)")
          )
          .map do |id, ticker, name, cusip, asset_class, price, div_yield, qty, mval, cost, gl, income|
            cost_f = cost.to_f
            gl_f   = gl.to_f
            {
              id:                id,
              security_id:       id,
              security_ticker:   ticker,
              security_name:     name,
              security_cusip:    cusip,
              security_label:    nil,
              as_of_date:        as_of,
              quantity:          qty.to_f.round(4),
              price:             price.to_f,
              market_value:      mval.to_f.round(2),
              cost_basis:        cost_f.round(2),
              unrealized_gl:     gl_f.round(2),
              unrealized_gl_pct: cost_f > 0 ? ((gl_f / cost_f) * 100).round(2) : 0.0,
              asset_class:       asset_class,
              est_annual_income: income.to_f.round(2),
              dividend_yield:    div_yield.to_f
            }
          end

        fill_resolved_cost_basis!(consolidated)
        fill_labels!(consolidated)

        total_cost = consolidated.sum { |p| p[:cost_basis] }
        total_gl   = consolidated.sum { |p| p[:unrealized_gl] }

        {
          as_of_date:        as_of,
          summary: {
            total_value:       total_value.round(2),
            total_cost_basis:  total_cost.round(2),
            unrealized_gl:     total_gl.round(2),
            est_annual_income: total_income.round(2)
          },
          by_asset_class:    by_asset_class,
          portfolio_history: history,
          positions:         consolidated
        }
      end

      # Combines brokerage position-snapshot history with daily crypto account-balance
      # history. Each series is carried forward from its own first date so early
      # brokerage dates don't pick up crypto that wasn't tracked yet.
      sig { returns(T.untyped) }
      def merged_portfolio_history
        # Ledger × adjusted closes where transaction history exists (split
        # cliffs and rewritten Plaid dates are impossible by construction);
        # snapshot batch sums remain only as the no-ledger fallback inside
        # the series.
        honest = ::Valuation::PortfolioSeries.call(from: 1.year.ago.to_date)
        # PortfolioSeries values everything it can see — ledger positions
        # and observation-only holdings alike — so nothing may be layered on
        # top of it (the old crypto overlay would double-count every coin).
        return honest if honest.any?

        # No priced ledger at all: fall back to the legacy snapshot batch
        # sums plus the computed crypto overlay (disjoint sources).
        brokerage = T.cast(
          ::PositionSnapshot
            .where.not(::Positions::CurrentPositions::COMPUTED_PREFIX_SQL)
            .group(:as_of_date)
            .order(:as_of_date)
            .sum(:market_value),
          T::Hash[T.untyped, T.untyped]
        ).transform_keys { |d| d.to_s }
          .transform_values(&:to_f)

        crypto = ::CryptoBalanceHistory.new.daily_totals
        return brokerage if crypto.empty?

        first_crypto_date = crypto.keys.min
        all_dates = (brokerage.keys + crypto.keys).uniq.sort

        last_brokerage = T.let(0.0, T.untyped)
        last_crypto    = T.let(0.0, T.nilable(Float))
        all_dates.each_with_object({}) do |date, h|
          last_brokerage = brokerage[date] if brokerage.key?(date)
          last_crypto    = crypto[date]    if crypto.key?(date)
          crypto_val     = date >= first_crypto_date ? last_crypto : 0.0
          h[date]        = (last_brokerage + crypto_val).round(2)
        end
      end

      private

      # Household-assigned display names. Kept out of the grouped query so
      # adding a label can't split a security into two rows.
      sig { params(positions: T.untyped).void }
      def fill_labels!(positions)
        labels = ::SecurityLabel.by_security(positions.map { |p| p[:security_id] })
        return if labels.empty?

        positions.each { |p| p[:security_label] = labels[p[:security_id]] }
      end

      # Lots, snapshot or ledger — Positions::ResolvedCostBasis decides, the
      # same way the security and cost-basis pages do. A snapshot basis keeps
      # the snapshot's own G/L; any other source recomputes it.
      sig { params(positions: T.untyped).void }
      def fill_resolved_cost_basis!(positions)
        resolver = ::Positions::ResolvedCostBasis.new(positions.map { |p| p[:id] })

        positions.each do |pos|
          resolved = resolver.resolve(pos[:id], quantity: pos[:quantity].to_f, snapshot_cost_basis: pos[:cost_basis])
          next unless resolved.source == ::Positions::ResolvedCostBasis::Source::Lots ||
                      resolved.source == ::Positions::ResolvedCostBasis::Source::Computed

          cost = resolved.cost_basis.round(2)
          gl   = (pos[:market_value] - cost).round(2)
          pos[:cost_basis]        = cost
          pos[:unrealized_gl]     = gl
          pos[:unrealized_gl_pct] = cost > 0 ? ((gl / cost) * 100).round(2) : 0.0
        end
      end
    end
  end
end
