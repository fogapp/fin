# typed: strict

module InvestmentLots
  class GenerateFromTransactions < T::Struct
    const :security_id, String


    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def preview
      build_lots(persist: false)
    end

    sig { params(replace: T::Boolean).returns(T::Array[::InvestmentLot]) }
    def commit!(replace:)
      ::InvestmentLot.transaction do
        ::InvestmentLot.where(security_id: security_id).destroy_all if replace
        build_lots(persist: true)
      end
    end

    private

    sig { params(persist: T::Boolean).returns(T.untyped) }
    def build_lots(persist:)
      # Purchases per account, oldest first
      purchases_by_account = ::InvestmentTransaction
        .joins(:transaction_type)
        .where(security_id: security_id)
        .where(transaction_types: { category: Positions::Rebuild::INBOUND_CATEGORIES })
        .order(:trade_date, :created_at)
        .includes(:account)
        .group_by(&:account_id)

      # Total shares sold per account. ABS(SUM(quantity)), not SUM(ABS):
      # sale-correction rows (positive quantity in a Sale category) net out
      # instead of consuming extra lots — the canonical form per
      # Positions::CostBasisCalculator.
      sales_by_account = ::InvestmentTransaction
        .joins(:transaction_type)
        .where(security_id: security_id)
        .where(transaction_types: { category: Positions::Rebuild::OUTBOUND_CATEGORIES })
        .group(:account_id)
        .sum(:quantity)
        .transform_values { |v| v.to_f.abs }

      result = []

      purchases_by_account.each do |account_id, purchases|
        sold_qty  = sales_by_account[account_id].to_f
        total_bought = purchases.sum { |t| t.quantity.to_f.abs }

        # If sold >= bought, the excess sales came from pre-import holdings.
        # Don't apply FIFO reduction — treat all imported purchases as surviving lots.
        remaining_to_consume = sold_qty >= total_bought ? 0.0 : sold_qty

        purchases.each do |txn|
          bought_qty = txn.quantity.to_f.abs
          next if bought_qty <= 0

          if remaining_to_consume >= bought_qty
            # Fully consumed by sales — skip this lot
            remaining_to_consume -= bought_qty
            next
          end

          lot_qty = (bought_qty - remaining_to_consume).round(6)
          remaining_to_consume = 0.0

          # Prefer cost_usd when present; otherwise fall back to amount + commissions
          cost_usd  = txn.cost_usd
          full_cost = if cost_usd.present? && cost_usd.abs > 0
            cost_usd.to_f.abs
          else
            txn.amount_usd.to_f.abs + txn.commissions_usd.to_f
          end

          # Pro-rate cost if the lot was partially consumed
          lot_cost = if lot_qty < bought_qty && bought_qty > 0
            (full_cost * (lot_qty / bought_qty)).round(4)
          else
            full_cost.round(4)
          end

          unit_cost = lot_qty > 0 ? (lot_cost / lot_qty).round(4) : nil

          if persist
            lot = ::InvestmentLot.create!(
              security_id:   security_id,
              account_id:    account_id,
              acquired_date: txn.trade_date,
              quantity:      lot_qty,
              cost_basis:    lot_cost,
              notes:         txn.description.presence
            )
            result << lot
          else
            result << {
              account_id:    account_id,
              account_name:  txn.account&.name,
              acquired_date: txn.trade_date.to_s,
              quantity:      lot_qty,
              cost_basis:    lot_cost,
              unit_cost:     unit_cost,
              description:   txn.description
            }
          end
        end
      end

      result
    end
  end
end
