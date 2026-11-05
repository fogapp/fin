# typed: strict

module MarketData
  # The one place provider rows become stored prices: daily candles, the
  # corporate actions extracted from an adjusted series, and (until stage 2
  # of the price consolidation) the legacy market_prices copy.
  #
  # Rows are {date:, open:, high:, low:, close:, adjusted_close:, volume:,
  # split_coefficient:, dividend_amount:} hashes; only the price columns a
  # row actually carries are written, so a close-only source (CoinGecko, a
  # CoinMarketCap spot) never blanks the OHLC another source stored for the
  # same day.
  module CandleWriter
    extend T::Sig

    PRICE_COLUMNS = T.let(%i[open high low close volume].freeze, T::Array[Symbol])

    # Upserts one daily candle per row (and its legacy copy). adjusted: false
    # stores close as the adjusted close — for series with no adjustment
    # (crypto, spot quotes). Returns the number of rows written.
    sig do
      params(security: Security, rows: T::Array[T::Hash[Symbol, T.untyped]], source: String,
             adjusted: T::Boolean, now: ActiveSupport::TimeWithZone).returns(Integer)
    end
    def self.write!(security, rows, source:, adjusted: true, now: Time.current)
      return 0 if rows.empty?

      columns = PRICE_COLUMNS.select { |column| T.must(rows.first).key?(column) }
      candles = rows.map do |row|
        row.select { |key, _| columns.include?(key) }.merge(
          security_id: security.id, date: row[:date], granularity: Candle::GRANULARITY_DAILY,
          adjusted_close: adjusted ? row[:adjusted_close] : row[:close],
          currency: "USD", source: source, created_at: now, updated_at: now
        )
      end
      Candle.upsert_all(candles, unique_by: %i[security_id granularity date])

      write_legacy!(security, rows, columns, adjusted: adjusted, now: now)
      rows.size
    end

    # Splits and dividends read off an adjusted daily series.
    sig do
      params(security: Security, rows: T::Array[T::Hash[Symbol, T.untyped]], source: String,
             now: ActiveSupport::TimeWithZone).void
    end
    def self.write_corporate_actions!(security, rows, source:, now: Time.current)
      actions = []
      rows.each do |row|
        if row[:split_coefficient] && row[:split_coefficient] != 1
          actions << { security_id: security.id, kind: "split", ex_date: row[:date],
                       ratio: row[:split_coefficient], amount: nil, currency: "USD",
                       source: source, created_at: now, updated_at: now }
        end
        if row[:dividend_amount]&.positive?
          actions << { security_id: security.id, kind: "dividend", ex_date: row[:date],
                       ratio: nil, amount: row[:dividend_amount], currency: "USD",
                       source: source, created_at: now, updated_at: now }
        end
      end
      CorporateAction.upsert_all(actions, unique_by: %i[security_id kind ex_date]) if actions.any?
    end

    # STAGE 2 REMOVAL POINT: legacy market_prices stays populated until the
    # candle store is backfilled in production and every reader goes through
    # PriceSeries (docs/price-consolidation.md). Deleting this method (and
    # its call above) is the whole of "stop the copy-back".
    sig do
      params(security: Security, rows: T::Array[T::Hash[Symbol, T.untyped]], columns: T::Array[Symbol],
             adjusted: T::Boolean, now: ActiveSupport::TimeWithZone).void
    end
    def self.write_legacy!(security, rows, columns, adjusted:, now:)
      attrs = rows.map do |row|
        row.select { |key, _| columns.include?(key) }.merge(
          security_id: security.id, date: row[:date],
          adjusted_close: adjusted ? row[:adjusted_close] : row[:close],
          created_at: now, updated_at: now
        )
      end
      MarketPrice.upsert_all(attrs, unique_by: %i[security_id date])
    end
    private_class_method :write_legacy!
  end
end
