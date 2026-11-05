# typed: strict

# Maintains the synthesized ("computed:") position snapshot for one
# (account, security) pair by rebuilding it from the FULL transaction ledger
# — never incrementally. Rebuilding is idempotent: reprocessing a
# transaction, re-syncing, or calling this twice cannot double-apply
# quantities (the old latest+delta approach did exactly that, and could
# adopt and corrupt a same-day Plaid holding row).
class RecalculatePositionService
  extend T::Sig

  # Single source of truth for position-affecting categories lives on
  # Positions::Rebuild; this alias keeps existing references working.
  POSITION_CATEGORIES = T.let(Positions::Rebuild::POSITION_CATEGORIES, T::Array[String])

  sig { params(transaction: InvestmentTransaction).void }
  def initialize(transaction:)
    @txn      = T.let(transaction, InvestmentTransaction)
    @security = T.let(transaction.security, T.nilable(Security))
    @account  = T.let(T.must(transaction.account), Account)
  end

  sig { returns(T.nilable(PositionSnapshot)) }
  def call
    security = @security
    return unless security
    return unless POSITION_CATEGORIES.include?(T.must(@txn.transaction_type).category)

    totals   = Positions::Ledger.totals(account_id: @account.id, security_id: security.id)
    net_qty  = totals.quantity
    net_cost = totals.cost

    # One computed row per (account, security). The LIKE suffix also matches
    # the legacy date-suffixed hashes so old rows are replaced, not doubled.
    existing = PositionSnapshot
      .where(account: @account, security: security)
      .where("source_row_hash LIKE ?", "computed:#{security.id}:#{@account.id}%")
      .order(as_of_date: :desc)
    snap = existing.first || PositionSnapshot.new(source_row_hash: "computed:#{security.id}:#{@account.id}")
    existing.where.not(id: snap.id).destroy_all if snap.persisted?

    if net_qty <= 0
      snap.destroy! if snap.persisted?
      return nil
    end

    price      = (MarketData::PriceSeries.latest_quote(security)&.price || snap.price.presence || latest_observed_price).to_d
    mkt_val    = (net_qty * price).round(4)
    unrealized = (mkt_val - net_cost).round(4)
    gl_pct     = net_cost > 0 ? ((unrealized / net_cost) * 100).round(4) : nil

    snap.assign_attributes(
      account:                  @account,
      security:                 security,
      as_of_date:               Date.current,
      quantity:                 net_qty.round(18),
      price:                    price,
      market_value:             mkt_val,
      cost_basis:               net_cost.round(4),
      unrealized_gain_loss:     unrealized,
      unrealized_gain_loss_pct: gl_pct
    )
    snap.save!
    snap
  rescue ActiveRecord::RecordNotUnique
    # A non-computed snapshot (e.g. a Plaid holding) already occupies this
    # (account, security, date) — the observation wins; nothing to add.
    nil
  end

  private

  # Last known price from any snapshot species for this pair — better than
  # silently valuing the position at zero when no price has been synced.
  sig { returns(T.untyped) }
  def latest_observed_price
    PositionSnapshot.where(account: @account, security: @security)
                    .order(as_of_date: :desc).limit(1).pick(:price)
  end
end
