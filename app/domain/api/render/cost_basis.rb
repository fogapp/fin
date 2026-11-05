# typed: strict

module Api
  module Render
    class CostBasis < Api::Render::Base
      extend T::Sig

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def index
        current     = ::Positions::CurrentPositions.new
        all_current = current.relation

        # ── Current position data (security-level) ─────────────────────────────
        current_rows = all_current
          .joins(:security)
          .group("position_snapshots.security_id", "securities.ticker", "securities.name", "position_snapshots.asset_class")
          .pluck(
            "position_snapshots.security_id",
            "securities.ticker",
            "securities.name",
            "position_snapshots.asset_class",
            Arel.sql("SUM(position_snapshots.quantity)"),
            Arel.sql("SUM(position_snapshots.market_value)")
          )
          .map do |sec_id, ticker, name, asset_class, qty, mval|
            {
              security_id:      sec_id,
              ticker:           ticker,
              name:             name,
              asset_class:      asset_class,
              current_quantity: qty.to_f,
              current_value:    mval.to_f
            }
          end

        security_ids = current_rows.map { |r| r[:security_id] }
        return { summary: empty_summary, positions: [] } if security_ids.empty?

        labels = ::SecurityLabel.by_security(security_ids)

        # ── Manual lots (user-defined, per security) ───────────────────────────
        lots_by_security = ::InvestmentLot
          .where(security_id: security_ids)
          .includes(:account)
          .group_by(&:security_id)
          .transform_values do |lots|
            lots.map do |lot|
              {
                id:            lot.id,
                account_id:    lot.account_id,
                account_name:  lot.account&.name,
                acquired_date: lot.acquired_date&.to_s,
                quantity:      lot.quantity.to_f,
                cost_basis:    lot.cost_basis.to_f,
                unit_cost:     lot.unit_cost,
                notes:         lot.notes
              }
            end
          end

        calculator = ::Positions::CostBasisCalculator.new(security_ids)
        resolver   = ::Positions::ResolvedCostBasis.new(security_ids)

        # ── Transaction counts ──────────────────────────────────────────────────
        txn_counts = ::InvestmentTransaction
          .joins(:transaction_type)
          .where(security_id: security_ids)
          .where(transaction_types: { category: ::Positions::Rebuild::POSITION_CATEGORIES })
          .group(:security_id)
          .count

        # ── Earliest trade date ─────────────────────────────────────────────────
        earliest_dates = ::InvestmentTransaction
          .joins(:transaction_type)
          .where(security_id: security_ids)
          .where(transaction_types: { category: ::Positions::Rebuild::POSITION_CATEGORIES })
          .group(:security_id)
          .minimum(:trade_date)

        # ── Assemble positions ──────────────────────────────────────────────────
        positions = current_rows.map do |row|
          sec_id  = row[:security_id]
          cur_qty = row[:current_quantity]
          cur_val = row[:current_value]

          lots     = lots_by_security[sec_id] || []
          coverage = calculator.coverage(sec_id, current_quantity: cur_qty)

          bought_qty = coverage&.bought_quantity || 0.0
          sold_qty   = coverage&.sold_quantity || 0.0
          net_qty    = coverage&.net_quantity || 0.0

          base = {
            security_id:          sec_id,
            ticker:               row[:ticker],
            name:                 row[:name],
            label:                labels[sec_id],
            asset_class:          row[:asset_class],
            current_quantity:     cur_qty.round(4),
            current_value:        cur_val.round(2),
            bought_quantity:      bought_qty.round(4),
            sold_quantity:        sold_qty.round(4),
            net_quantity:         net_qty.round(4),
            transaction_count:    txn_counts[sec_id].to_i,
            earliest_transaction: earliest_dates[sec_id]&.to_s
          }

          if lots.any?
            # Use manually-defined lots
            lot_qty   = lots.sum { |l| l[:quantity] }
            lot_basis = lots.sum { |l| l[:cost_basis] }

            # "complete" means the lots cover enough that every other page
            # reports them as the basis (Positions::ResolvedCostBasis).
            gap_qty = [ 0.0, cur_qty - lot_qty ].max
            status  = if cur_qty < 0.0001 || ::Positions::ResolvedCostBasis.covered?(resolver.lot_coverage(sec_id, quantity: cur_qty))
              "complete"
            elsif lot_qty > 0
              "partial"
            else
              "unknown"
            end

            base.merge(
              gap_quantity:        gap_qty.round(4),
              computed_cost_basis: lot_basis.round(2),
              avg_cost_per_share:  lot_qty > 0 ? (lot_basis / lot_qty).round(4) : nil,
              unrealized_gl:       (cur_val - lot_basis).round(2),
              status:              status,
              lots:                lots
            )
          else
            # Fall back to the shared average-cost computation
            gap_qty             = [ 0.0, cur_qty - net_qty ].max
            covered_qty         = coverage&.covered_quantity || 0.0
            computed_cost_basis = coverage&.cost_basis
            unrealized_gl       = computed_cost_basis ? (cur_val - computed_cost_basis) : nil

            status = if cur_qty < 0.0001
              "complete"
            elsif covered_qty == 0
              "unknown"
            elsif ::Positions::ResolvedCostBasis.covered?(covered_qty / cur_qty)
              "complete"
            else
              "partial"
            end

            base.merge(
              gap_quantity:        gap_qty.round(4),
              computed_cost_basis: computed_cost_basis&.round(2),
              avg_cost_per_share:  coverage&.avg_cost_per_share&.round(4),
              unrealized_gl:       unrealized_gl&.round(2),
              status:              status,
              lots:                []
            )
          end
        end

        positions.sort_by! { |p| -p[:current_value] }

        # ── Summary ─────────────────────────────────────────────────────────────
        {
          summary: {
            total_positions:  positions.size,
            complete:         positions.count { |p| p[:status] == "complete" },
            partial:          positions.count { |p| p[:status] == "partial" },
            unknown:          positions.count { |p| p[:status] == "unknown" },
            total_value:      positions.sum { |p| p[:current_value] }.round(2),
            known_cost_basis: positions
              .select { |p| %w[complete partial].include?(p[:status]) }
              .sum { |p| p[:computed_cost_basis].to_f }
              .round(2)
          },
          positions: positions
        }
      end

      private

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def empty_summary
        { total_positions: 0, complete: 0, partial: 0, unknown: 0,
          total_value: 0.0, known_cost_basis: 0.0 }
      end
    end
  end
end
