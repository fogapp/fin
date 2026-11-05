# typed: true

# What happened to a grant after it was awarded: exercises and settlements
# (which acquire shares and must stay within what has vested), sales (which
# must stay within what was acquired), and cancellations (which shave the
# unvested tail — departures, repricings).
#
# NOTE: the `method` column shadows Object#method on instances; always read
# it via `self[:method]` / `event[:method]` inside app code.
class EquityGrantEvent < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  # Feeds the cached tax report (render_cached), so writes must rotate the key.
  include BumpsHouseholdDataVersion

  # What the event did to the grant's shares.
  class Kind < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Exercise = new("exercise")
      Settlement = new("settlement")
      Sale = new("sale")
      Cancellation = new("cancellation")
    end
  end

  # How an acquisition was funded/settled. Named SettlementMethod (not
  # Method) so the nested constant doesn't shadow ::Method — the `method`
  # column already shadows Object#method on instances.
  class SettlementMethod < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Cash = new("cash")
      Cashless = new("cashless")
      SellToCover = new("sell_to_cover")
      NetSettlement = new("net_settlement")
    end
  end

  # Who bought the shares in a sale.
  class BuyerType < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      CompanyTender = new("company_tender")
      ThirdParty = new("third_party")
    end
  end

  # Kinds that acquire shares (and so may carry a settlement method).
  ACQUIRING_KINDS = T.let([ Kind::Exercise, Kind::Settlement ].freeze, T::Array[Kind])

  belongs_to :equity_grant

  typed_enum :kind, Kind
  typed_enum :method, SettlementMethod, allow_nil: true
  typed_enum :buyer_type, BuyerType, allow_nil: true

  validates :occurred_on, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validate :method_only_for_acquisitions
  validate :buyer_type_only_for_sales
  validate :quantity_within_limits, on: :create

  private

  def method_only_for_acquisitions
    return if self[:method].blank? || ACQUIRING_KINDS.include?(kind)

    errors.add(:method, "only applies to exercises and settlements")
  end

  def buyer_type_only_for_sales
    return if buyer_type.blank? || kind == Kind::Sale

    errors.add(:buyer_type, "only applies to sales")
  end

  # Exercises/settlements can't outrun vesting as of their date; sales can't
  # outrun the shares actually acquired.
  def quantity_within_limits
    grant = equity_grant
    return if grant.nil? || quantity.blank? || occurred_on.blank?

    case kind
    when Kind::Exercise, Kind::Settlement
      prior = sibling_events.where(kind: kind).where(occurred_on: ..occurred_on).sum(:quantity).to_d
      errors.add(:quantity, "exceeds vested shares") if prior + quantity.to_d > grant.vested_quantity(occurred_on)
    when Kind::Sale
      sold     = sibling_events.where(kind: Kind::Sale).sum(:quantity).to_d
      acquired = sibling_events.where(kind: ACQUIRING_KINDS).sum(:quantity).to_d
      errors.add(:quantity, "exceeds exercised or settled shares") if sold + quantity.to_d > acquired
    end
  end

  def sibling_events
    EquityGrantEvent.where(equity_grant_id: equity_grant_id).where.not(id: id)
  end
end
