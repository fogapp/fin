# typed: strict

module MarketData
  # The custodian's own daily price for instruments no market-data provider
  # covers — municipal bonds with no ticker, private-fund interests,
  # non-traded BDCs. Holdings syncs report a price for every position, but
  # PositionSnapshot rows are upserted in place, so without this the only
  # price such an instrument ever had was whatever the latest sync left on
  # the snapshot, and every valuation held it flat for months.
  #
  # Each observation lands as a close-only daily candle with source
  # "custodian" (and its legacy market_prices copy, until the price
  # consolidation's stage 2 retires that table). Prices are stored as quoted — bonds per 100 of face — and
  # the valuation engines apply the quoting scale, exactly as they do for the
  # snapshot fallback price.
  #
  # A market provider's close always outranks the custodian's: a custodian
  # write never replaces a provider candle (or a legacy-only market price),
  # while a provider write upserts over a custodian candle for the same day.
  module CustodianPrices
    extend T::Sig

    SOURCE = "custodian"

    # A candle link that keeps failing means the provider can't price the
    # instrument after all (a ticker it doesn't carry); the custodian's price
    # beats nothing.
    FAILING_LINK_THRESHOLD = 3
    # A provider close this recent means market data covers the instrument.
    MARKET_FRESHNESS_DAYS = 14

    # Records one observed price. Returns whether a close was written.
    sig do
      params(security: Security, date: Date, price: T.nilable(BigDecimal),
             quantity: T.nilable(BigDecimal), market_value: T.nilable(BigDecimal)).returns(T::Boolean)
    end
    def self.record!(security, date:, price:, quantity: nil, market_value: nil)
      return false if price.nil? || !price.positive?
      return false unless eligible?(security)

      remember_quote_basis!(security, price: price, quantity: quantity, market_value: market_value)
      write!(security, [ { date: date, close: price } ]).positive?
    end

    # Whether the custodian should price this instrument: no configured
    # provider can (no ticker, an unpriceable class), its link is disabled or
    # keeps failing, and no provider close has landed recently.
    sig { params(security: Security).returns(T::Boolean) }
    def self.eligible?(security)
      return false if market_closes_since?(security, Date.current - MARKET_FRESHNESS_DAYS)
      return true unless Router.available_for?(security, Capability::Candles)

      link = InstrumentDataLink.find_by(security_id: security.id, capability: Capability::Candles)
      return false if link.nil?

      link.disabled? || link.consecutive_failures >= FAILING_LINK_THRESHOLD
    end

    # Upserts custodian closes, skipping any date a market source already
    # priced. Returns the number of rows written.
    sig { params(security: Security, rows: T::Array[T::Hash[Symbol, T.untyped]]).returns(Integer) }
    def self.write!(security, rows)
      dates = rows.map { |row| row[:date] }
      custodian_dates = Candle.daily.where(security_id: security.id, date: dates, source: SOURCE).pluck(:date)
      taken = Candle.daily.where(security_id: security.id, date: dates).where.not(source: SOURCE).pluck(:date)
      # A legacy-only market price (no candle yet) came from a provider too.
      taken += MarketPrice.where(security_id: security.id, date: dates).where.not(date: custodian_dates).pluck(:date)
      free = rows.reject { |row| taken.include?(row[:date]) }.uniq { |row| row[:date] }
      return 0 if free.empty?

      CandleWriter.write!(security, free, source: SOURCE, adjusted: false)
    end

    # Bonds report quantity as face amount and price per 100 of it. Stamped
    # on the security while a snapshot still shows both, so a valuation can
    # scale correctly once the position is sold and its snapshot reads 0.
    sig do
      params(security: Security, price: BigDecimal, quantity: T.nilable(BigDecimal),
             market_value: T.nilable(BigDecimal)).void
    end
    def self.remember_quote_basis!(security, price:, quantity:, market_value:)
      return if quantity.nil? || market_value.nil? || quantity.zero? || market_value.zero?

      per_hundred = Positions::PriceScale.from_ratio(quantity: quantity, price: price, market_value: market_value) == 0.01
      return if security.quoted_per_hundred? == per_hundred

      attrs = (security.instrument_attributes || {}).merge(Security::QUOTE_BASIS_KEY => per_hundred ? Security::QUOTE_BASIS_PER_HUNDRED : nil).compact
      security.update_column(:instrument_attributes, attrs)
    end

    sig { params(security: Security, since: Date).returns(T::Boolean) }
    def self.market_closes_since?(security, since)
      Candle.daily.where(security_id: security.id, date: since..).where.not(source: SOURCE).exists?
    end
    private_class_method :market_closes_since?
  end
end
