# typed: strict

module Positions
  # Average-cost fallback for positions whose snapshots carry no cost basis:
  # aggregates purchases and sales per security and derives the cost of the
  # currently held quantity.
  #
  # Previously this math lived in two renderers with a real behavioral fork
  # (SUM(ABS(quantity)) vs ABS(SUM(quantity)) for sales), so the portfolio
  # and cost-basis pages could disagree about the same security. Canonical
  # form: sold quantity is ABS(SUM(quantity)) — corrections (positive rows in
  # a Sale category) net against sales instead of double-counting.
  class CostBasisCalculator
    extend T::Sig

    Coverage = Struct.new(:bought_quantity, :bought_cost, :sold_quantity,
                          :net_quantity, :avg_cost_per_share, :covered_quantity,
                          :cost_basis, keyword_init: true)

    sig { params(security_ids: T::Array[T.untyped]).void }
    def initialize(security_ids)
      @security_ids = security_ids
    end

    # {security_id => {bought_quantity:, bought_cost:}}
    sig { returns(T::Hash[T.untyped, T::Hash[Symbol, Float]]) }
    def purchases
      @purchases ||= T.let(
        InvestmentTransaction
              .joins(:transaction_type)
              .where(security_id: @security_ids, transaction_types: { category: Rebuild::INBOUND_CATEGORIES })
              .group(:security_id)
              .pluck(
                :security_id,
                Arel.sql("SUM(quantity)"),
                Arel.sql("SUM(ABS(amount_usd) + COALESCE(commissions_usd, 0))")
              )
              .each_with_object({}) do |(sid, qty, cost), h|
                h[sid] = { bought_quantity: qty.to_f, bought_cost: cost.to_f }
              end,
        T.nilable(T::Hash[T.untyped, T::Hash[Symbol, Float]]),
      )
    end

    # {security_id => sold quantity (positive)}
    sig { returns(T::Hash[T.untyped, Float]) }
    def sold_quantities
      @sold_quantities ||= T.let(
        InvestmentTransaction
              .joins(:transaction_type)
              .where(security_id: @security_ids, transaction_types: { category: Rebuild::OUTBOUND_CATEGORIES })
              .group(:security_id)
              .pluck(:security_id, Arel.sql("SUM(quantity)"))
              .each_with_object({}) { |(sid, qty), h| h[sid] = qty.to_f.abs },
        T.nilable(T::Hash[T.untyped, Float]),
      )
    end

    # Average-cost coverage of the currently held quantity; nil when there is
    # no purchase history to derive a basis from.
    sig { params(security_id: T.untyped, current_quantity: Float).returns(T.nilable(Coverage)) }
    def coverage(security_id, current_quantity:)
      p_data = purchases[security_id]
      return nil unless p_data && T.must(p_data[:bought_quantity]) > 0

      bought_qty  = T.must(p_data[:bought_quantity])
      bought_cost = T.must(p_data[:bought_cost])
      sold_qty    = sold_quantities[security_id].to_f
      net_qty     = bought_qty - sold_qty
      covered_qty = [ [ net_qty, current_quantity ].min, 0.0 ].max
      avg_cost    = bought_cost / bought_qty

      Coverage.new(
        bought_quantity:    bought_qty,
        bought_cost:        bought_cost,
        sold_quantity:      sold_qty,
        net_quantity:       net_qty,
        avg_cost_per_share: avg_cost,
        covered_quantity:   covered_qty,
        cost_basis:         covered_qty > 0 ? (avg_cost * covered_qty) : nil
      )
    end
  end
end
