# typed: true

# A single equity award. The vesting schedule is either flat
# (interval × occurrences with an optional cliff, cumulative-rounded) or an
# explicit custom_tranches array; all vested/unvested numbers are derived by
# Equity::VestingCalculator, never stored.
class EquityGrant < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  # Grants are an asset class in net worth (render_cached), so writes must
  # rotate the key.
  include BumpsHouseholdDataVersion

  # Award flavor: options (iso/nso) carry a strike price, full-value awards
  # (rsu/rsa) must not.
  class GrantType < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Iso = new("iso")
      Nso = new("nso")
      Rsu = new("rsu")
      Rsa = new("rsa")
    end
  end

  # Cadence of a flat vesting schedule (interval × occurrences).
  class VestingInterval < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Monthly = new("monthly")
      Quarterly = new("quarterly")
      Annual = new("annual")
    end
  end

  # Grant types that are options (exercisable, strike-priced). An array of
  # GrantType members rather than a separate enum — a parallel OptionType
  # enum would never compare equal to the grant_type column's GrantType
  # instances.
  OPTION_TYPES = T.let([ GrantType::Iso, GrantType::Nso ].freeze, T::Array[GrantType])

  belongs_to :equity_company
  has_many :events, class_name: "EquityGrantEvent", dependent: :destroy

  before_validation :default_vesting_commencement_date

  typed_enum :grant_type, GrantType
  typed_enum :vesting_interval, VestingInterval, allow_nil: true

  validates :grant_date, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :vesting_occurrences, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :cliff_installments, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :strike_price_matches_type
  validate :vesting_interval_required_for_flat_schedule
  validate :custom_tranches_shape

  sig { returns(T::Boolean) }
  def option?
    OPTION_TYPES.include?(grant_type)
  end

  sig { returns(Equity::VestingCalculator) }
  def calculator
    Equity::VestingCalculator.new(self)
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def tranches
    calculator.tranches
  end

  sig { params(as_of: Date).returns(BigDecimal) }
  def vested_quantity(as_of = Date.current)
    calculator.vested_quantity(as_of)
  end

  sig { returns(BigDecimal) }
  def exercised_quantity
    event_total(EquityGrantEvent::Kind::Exercise)
  end

  sig { returns(BigDecimal) }
  def settled_quantity
    event_total(EquityGrantEvent::Kind::Settlement)
  end

  sig { returns(BigDecimal) }
  def sold_quantity
    event_total(EquityGrantEvent::Kind::Sale)
  end

  private

  sig { params(kind: EquityGrantEvent::Kind).returns(BigDecimal) }
  def event_total(kind)
    if events.loaded?
      events.select { |e| e.kind == kind }.sum(BigDecimal("0")) { |e| e.quantity.to_d }
    else
      events.where(kind: kind).sum(:quantity).to_d
    end
  end

  def default_vesting_commencement_date
    self.vesting_commencement_date ||= grant_date
  end

  def strike_price_matches_type
    if option?
      errors.add(:strike_price, "is required for #{grant_type} grants") if strike_price.blank?
    elsif strike_price.present?
      errors.add(:strike_price, "must be blank for #{grant_type} grants")
    end
  end

  def vesting_interval_required_for_flat_schedule
    return if custom_tranches.present?
    return unless vesting_occurrences.to_i.positive?

    errors.add(:vesting_interval, "is required for a flat vesting schedule") if vesting_interval.blank?
  end

  def custom_tranches_shape
    return if custom_tranches.blank?

    valid = custom_tranches.is_a?(Array) && custom_tranches.all? do |t|
      t.is_a?(Hash) &&
        (Date.iso8601(t["date"].to_s) rescue nil).present? &&
        t["quantity"].to_d.positive?
    end
    errors.add(:custom_tranches, "must be an array of {date, quantity} entries") unless valid
  end
end
