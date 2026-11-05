# typed: strict

module Positions
  # Net quantity and cost for one (account, instrument) pair, read off the
  # FULL position-affecting ledger. The one definition behind both the
  # positions table (Rebuild) and the synthesized computed: snapshots
  # (RecalculatePositionService), so the two can never net differently.
  module Ledger
    extend T::Sig

    Totals = Struct.new(:quantity, :cost, :first_acquired_on, keyword_init: true)

    # Quantities and costs are normalized with ABS: providers disagree on
    # whether a sale's quantity/cost is negative. Cost prefers cost_usd, then
    # amount_usd. Cost never goes below zero (proceeds beyond basis are a
    # realized gain, not negative basis).
    COST_SQL = "ABS(COALESCE(cost_usd, amount_usd, 0))"

    # Quantities are in the instrument's current share units (see
    # SplitAdjustment): 10 shares bought before a 4:1 split net as 40, the
    # units the custodian reports and adjusted closes are quoted in.
    sig { params(account_id: String, security_id: String).returns(Totals) }
    def self.totals(account_id:, security_id:)
      by_pair = totals_by_pair(InvestmentTransaction.where(account_id: account_id, security_id: security_id))
      by_pair.fetch([ account_id, security_id ]) { empty_totals }
    end

    # totals for every (account, instrument) pair in `transactions`, keyed
    # [account_id, security_id], in two grouped reads however many pairs
    # there are — the nightly rebuild walks every pair a household has.
    sig { params(transactions: ActiveRecord::Relation).returns(T::Hash[[ String, String ], Totals]) }
    def self.totals_by_pair(transactions)
      ledger = transactions.joins(:transaction_type)
                           .where(transaction_types: { category: Rebuild::POSITION_CATEGORIES })
      inbound = Arel.sql(InvestmentTransaction.sanitize_sql_array(
        [ "transaction_types.category IN (?)", Rebuild::INBOUND_CATEGORIES ]
      ))

      quantities = ledger.group(:account_id, :security_id, inbound, :trade_date).sum(:quantity)
      costs = ledger.group(:account_id, :security_id, inbound)
                    .pluck(:account_id, :security_id, inbound,
                           Arel.sql("COALESCE(SUM(#{COST_SQL}), 0)"), Arel.sql("MIN(trade_date)"))
      splits = SplitAdjustment.splits_by_security(quantities.keys.map { |key| key[1] }.uniq)

      # Net split-adjusted quantity per pair and direction, ABS'd as a whole.
      net_qty = Hash.new { |h, k| h[k] = BigDecimal("0") }
      quantities.each do |(account_id, security_id, is_inbound, date), qty|
        net_qty[[ account_id, security_id, is_inbound ]] += qty.to_d * SplitAdjustment.factor(splits[security_id], date)
      end

      directions = costs.to_h { |account_id, security_id, is_inbound, cost, first| [ [ account_id, security_id, is_inbound ], [ cost, first ] ] }
      directions.keys.map { |key| key.first(2) }.uniq.to_h do |pair|
        bought_cost, first_acquired_on = directions[[ *pair, true ]]
        sold_cost, _ = directions[[ *pair, false ]]
        quantity = net_qty.fetch([ *pair, true ], BigDecimal("0")).abs - net_qty.fetch([ *pair, false ], BigDecimal("0")).abs
        cost = [ bought_cost.to_d - sold_cost.to_d, BigDecimal("0") ].max

        [ pair, Totals.new(quantity: quantity, cost: cost, first_acquired_on: first_acquired_on) ]
      end
    end

    sig { returns(Totals) }
    def self.empty_totals
      Totals.new(quantity: BigDecimal("0"), cost: BigDecimal("0"), first_acquired_on: nil)
    end
    private_class_method :empty_totals
  end
end
