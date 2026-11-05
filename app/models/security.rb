# typed: true

class Security < ApplicationRecord
  extend T::Sig

  has_many :investment_transactions, dependent: :restrict_with_error
  has_many :market_prices, dependent: :destroy
  has_many :position_snapshots, dependent: :restrict_with_error
  has_one  :overview, class_name: "SecurityOverview", dependent: :destroy
  has_many :news_articles, class_name: "SecurityNewsArticle", dependent: :destroy
  has_many :security_watches, dependent: :destroy
  has_many :security_labels, dependent: :destroy
  has_many :instrument_identifiers, dependent: :destroy
  include EmitsWorkflowEvents

  # Legacy provider-derived security_type vocabulary is open-ended, so it
  # stays a plain string — but crypto detection sites share this constant.
  CRYPTO_TYPE = "Crypto"

  # instrument_attributes["quote_basis"]: how the instrument's price is
  # quoted. Bonds quote per 100 of face value (quantity is the face amount),
  # learned from custodian snapshots — see MarketData::CustodianPrices.
  QUOTE_BASIS_KEY = "quote_basis"
  QUOTE_BASIS_PER_HUNDRED = "per_100_face"

  validates :cusip, uniqueness: true, allow_blank: true
  typed_enum :instrument_class, Instruments::InstrumentClass

  # Rows created outside Instruments::Resolver (factories, console, legacy
  # paths) still register their identifiers, keeping the registry complete.
  after_create :register_instrument_identifiers

  scope :of_class, ->(klass) { where(instrument_class: klass) }
  scope :crypto,     -> { of_class(Instruments::InstrumentClass::Crypto) }
  scope :non_crypto, -> { where.not(instrument_class: Instruments::InstrumentClass::Crypto) }

  scope :with_ticker, -> { where.not(ticker: [ nil, "" ]) }
  # Watchlists are per household; securities themselves are shared market
  # data. SecurityWatch is unscoped here because these scopes are used from
  # jobs with no Current.household as well as inside requests.
  scope :watched_by, ->(household) {
    where(id: SecurityWatch.unscoped.where(household_id: household.id).select(:security_id))
  }
  scope :watched_by_anyone, -> {
    where(id: SecurityWatch.unscoped.select(:security_id))
  }

  sig { params(household: T.nilable(Household)).returns(T::Boolean) }
  def watched_by?(household)
    return false if household.nil?

    SecurityWatch.unscoped.exists?(household_id: household.id, security_id: id)
  end

  sig { returns(T::Boolean) }
  def quoted_per_hundred?
    (instrument_attributes || {})[QUOTE_BASIS_KEY] == QUOTE_BASIS_PER_HUNDRED
  end

  sig { returns(T.nilable(String)) }
  def display_name
    [ ticker, name ].compact_blank.join(" — ").presence || cusip
  end

  JUNK_TAIL_MARKERS = [
    "CORPORATE ACTION",
    "CORP ACTION",
    "EVENT:",
    "CASH IN LIEU",
    "STOCK SPLIT",
    "MERGER",
    "TENDER OFFER",
    "SPINOFF",
    "FRACTIONAL"
  ].freeze

  JUNK_START_PATTERNS = [
    /\ATRANSFER\b/i,
    /\ADEPOSIT\s+SWEEP/i,
    /\AWIRE\b/i,
    /\ACHECK\s+/i
  ].freeze

  sig { params(description: T.nilable(String)).returns(T.nilable(String)) }
  def self.sanitize_name(description)
    return nil if description.blank?
    name = description.to_s.split(" @ ").first.to_s.strip
    JUNK_TAIL_MARKERS.each do |marker|
      if (i = name.upcase.index(marker.upcase))
        name = name[0, i].to_s.strip
      end
    end
    return nil if JUNK_START_PATTERNS.any? { |p| name.match?(p) }
    return nil if name.blank?
    name
  end

  sig { returns(T::Boolean) }
  def junk_name?
    return true if name.blank?
    Security::JUNK_TAIL_MARKERS.any? { |m| T.must(name).upcase.include?(m) } ||
      Security::JUNK_START_PATTERNS.any? { |p| T.must(name).match?(p) }
  end

  # Monitor/alert fields (whitelisted in Workflows::Catalog): the freshest
  # known price, its staleness, and the 24h move where the provider gives one.
  sig { returns(T.nilable(Float)) }
  def current_price
    MarketData::PriceSeries.latest_quote(self)&.price&.to_f
  end

  sig { returns(T.nilable(Integer)) }
  def price_age_days
    MarketData::PriceSeries.latest_quote(self)&.age_days
  end

  sig { returns(T.nilable(Float)) }
  def day_change_pct
    InstrumentQuote.find_by(security_id: id)&.change_pct_24h&.to_f
  end

  sig { returns(String) }
  def to_param
    ticker.presence || id.to_s
  end

  sig { void }
  def register_instrument_identifiers
    identifiers = { "cusip" => cusip }
    identifiers[Instruments::Resolver.symbol_scheme(instrument_class)] = ticker.to_s.upcase.strip if ticker.present?
    Instruments::Resolver.register!(self, identifiers)
  end

  sig { params(param: String).returns(Security) }
  def self.find_by_param!(param)
    by_ticker = where("UPPER(ticker) = ?", param.to_s.upcase)
                  .left_joins(:investment_transactions)
                  .group("securities.id")
                  .order(Arel.sql("COUNT(investment_transactions.id) DESC"))
                  .first
    return by_ticker if by_ticker
    find(param)
  end
end
