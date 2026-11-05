# typed: true

# A property the household owns. Its value over time is the set of
# RealEstateValuation rows attached to it; this model's job is to turn those
# into a single current value and a carry-forward series net worth can use.
#
# Works with or without the RentCast integration: without a key, the user
# enters values by hand and every automatic path is simply never taken.
class RealEstateProperty < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include BumpsHouseholdDataVersion

  # Sold properties keep their history but stop contributing to net worth
  # from the sale date forward — the proceeds show up in a cash account, so
  # carrying the asset past the sale would double-count.
  class Status < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Owned = new("owned")
      Sold  = new("sold")
    end
  end

  # How long a facts cache (beds/baths/sqft, tax assessments, sale history)
  # stays fresh before a refresh spends a second request on GET /properties.
  FACTS_TTL = 90.days

  typed_enum :status, Status

  has_many :valuations,
           -> { order(:as_of) },
           class_name: "RealEstateValuation",
           dependent:  :destroy
  # Mortgages financing this property. The FK lives on loans and nullifies,
  # so deleting a property unlinks its loan rather than destroying it.
  has_many :loans, dependent: :nullify

  validates :name, :address_line1, presence: true
  validates :purchase_price, :sold_price,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :sold_properties_have_a_sale_date

  # Only when the columns they mirror change — PropertyRefresher saves
  # several times per refresh touching sync bookkeeping alone.
  after_save :sync_purchase_valuation, if: :purchase_details_changed?
  after_save :sync_sale_valuation,     if: :sale_details_changed?

  scope :owned, -> { where(status: Status::Owned.serialize) }
  scope :syncable, -> { owned.where(sync_enabled: true) }

  sig { returns(T::Boolean) }
  def sold? = status == Status::Sold

  # The address string handed to RentCast. Prefers the canonical form the
  # API returned on a previous lookup, since re-sending our own formatting
  # can resolve to a different record.
  #
  # RentCast documents "Street, City, State, Zip" — comma-separated
  # throughout, zip included. Joining state and zip with a space instead
  # makes some addresses fail to geolocate.
  sig { returns(String) }
  def query_address
    return T.must(formatted_address) if formatted_address.present?

    [ [ address_line1, address_line2 ].compact_blank.join(" "), city, state, zip_code ]
      .compact_blank.join(", ")
  end

  # Newest market-source valuation, with the same-day tiebreak in
  # RealEstateValuation::SOURCE_RANK. Loaded in Ruby rather than SQL — a
  # property has tens of rows, not thousands, and `valuations` is usually
  # already preloaded by the caller.
  sig { returns(T.nilable(RealEstateValuation)) }
  def current_valuation
    market_valuations.max_by(&:precedence)
  end

  sig { returns(T.nilable(BigDecimal)) }
  def current_value
    current_valuation&.amount
  end

  # Current balance of the linked mortgages. Nil (not zero) when no loan is
  # linked, so the UI can tell "no mortgage" from "paid off". Memoized —
  # serialize, equity, loan_to_value and totals each read it, and every read
  # replays the loans' amortization. Cleared on reload.
  sig { returns(T.nilable(BigDecimal)) }
  def mortgage_balance
    return @mortgage_balance if defined?(@mortgage_balance)

    active = loans.select { |loan| loan.status == Loan::Status::Active }
    @mortgage_balance = T.let(
      active.empty? ? nil : active.sum(BigDecimal("0")) { |loan| loan.current_balance },
      T.nilable(BigDecimal)
    )
  end

  sig { params(options: T.untyped).returns(T.self_type) }
  def reload(*options)
    remove_instance_variable(:@mortgage_balance) if defined?(@mortgage_balance)
    super
  end

  sig { returns(T.nilable(BigDecimal)) }
  def equity
    value = current_value
    return nil if value.nil?

    value - (mortgage_balance || 0)
  end

  # Loan-to-value as a percentage, nil without both a value and a mortgage.
  sig { returns(T.nilable(Float)) }
  def loan_to_value
    value   = current_value
    balance = mortgage_balance
    return nil if value.nil? || balance.nil? || value.zero?

    ((balance / value) * 100).to_f.round(1).to_f
  end

  # Carry-forward breakpoints for net worth: [date, value] pairs from market
  # valuations only, one per date (precedence decides ties), with a zero
  # point the day after a sale so the asset drops off cleanly.
  sig { returns(T::Array[[ Date, Float ]]) }
  def value_breakpoints
    by_date = market_valuations.group_by(&:as_of)
    points  = by_date.map { |date, rows| [ date, T.must(rows.max_by(&:precedence)).amount.to_f ] }
    points.sort_by!(&:first)

    if sold? && (ended = sold_date)
      points.reject! { |date, _| date > ended }
      points << [ ended + 1, 0.0 ]
    end

    points
  end

  # Idempotent write of one point. Re-syncing the same (source, date)
  # updates in place rather than stacking, matching the unique index.
  sig do
    params(
      source: RealEstateValuation::Source, as_of: Date, amount: T.any(BigDecimal, Float, Integer),
      value_low: T.untyped, value_high: T.untyped, payload: T.untyped
    ).returns(RealEstateValuation)
  end
  def record_valuation!(source:, as_of:, amount:, value_low: nil, value_high: nil, payload: nil)
    valuation = RealEstateValuation.find_or_initialize_by(
      real_estate_property_id: id, source: source.serialize, as_of: as_of
    )
    valuation.assign_attributes(
      household_id: household_id, amount: amount,
      value_low: value_low, value_high: value_high, payload: payload
    )
    valuation.save!
    association(:valuations).reset
    valuation
  end

  private

  sig { returns(T::Array[RealEstateValuation]) }
  def market_valuations
    valuations.select { |valuation| RealEstateValuation::MARKET_SOURCES.include?(valuation.source) }
  end

  sig { returns(T::Boolean) }
  def purchase_details_changed?
    saved_change_to_purchase_date? || saved_change_to_purchase_price?
  end

  sig { returns(T::Boolean) }
  def sale_details_changed?
    saved_change_to_status? || saved_change_to_sold_date? || saved_change_to_sold_price?
  end

  # The purchase price is a real market data point (an arm's-length sale),
  # so it anchors the left edge of the chart. Kept in step with the columns
  # rather than written once, so correcting a typo moves the point.
  sig { void }
  def sync_purchase_valuation
    date, price = purchase_date, purchase_price
    if date.blank? || price.blank?
      valuations.where(source: RealEstateValuation::Source::Purchase.serialize).destroy_all
      return
    end

    existing = valuations.where(source: RealEstateValuation::Source::Purchase.serialize).to_a
    existing.reject { |valuation| valuation.as_of == date }.each(&:destroy)
    record_valuation!(source: RealEstateValuation::Source::Purchase, as_of: date, amount: price)
  end

  sig { void }
  def sync_sale_valuation
    return unless sold?

    date, price = sold_date, sold_price
    return if date.blank? || price.blank?

    record_valuation!(source: RealEstateValuation::Source::Sale, as_of: date, amount: price)
  end

  sig { void }
  def sold_properties_have_a_sale_date
    errors.add(:sold_date, "is required when a property is marked sold") if sold? && sold_date.blank?
  end
end
