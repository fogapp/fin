# typed: strict

module MarketData
  # The single read API for prices: adjusted daily closes for charts and
  # valuation, and the freshest available spot with explicit staleness.
  module PriceSeries
    extend T::Sig

    Spot = Struct.new(:price, :currency, :as_of, :source, keyword_init: true) do
      extend T::Sig

      sig { returns(T.nilable(Integer)) }
      def age_days
        return nil if as_of.nil?

        ((Time.current - as_of.to_time) / 1.day).floor
      end
    end

    # [[date, adjusted_close_decimal], ...] ascending. Candles win per date;
    # legacy market_prices fill the dates candles don't cover yet, so one
    # fresh candle can never erase an instrument's price history while the
    # candle store backfills.
    sig { params(security: Security, from: T.nilable(Date), to: Date).returns(T::Array[[ Date, BigDecimal ]]) }
    def self.daily_closes(security, from: nil, to: Date.current)
      candles = Candle.daily.where(security_id: security.id).where(date: ..to)
      legacy  = MarketPrice.where(security_id: security.id).where(date: ..to)
      if from
        candles = candles.where(date: from..)
        legacy  = legacy.where(date: from..)
      end

      merged = legacy.pluck(:date, Arel.sql("COALESCE(adjusted_close, close)")).to_h
      merged.merge!(candles.pluck(:date, Arel.sql("COALESCE(adjusted_close, close)")).to_h)
      merged.sort.map { |d, c| [ d, c.to_d ] }
    end

    # daily_closes for many instruments in two queries instead of two per
    # instrument. Same candles-over-legacy precedence, same COALESCE. Returns
    # {security_id => {date => adjusted_close}}; instruments with no prices in
    # their window are simply absent.
    #
    # `windows` is {security_id => earliest date that instrument needs}. Each
    # instrument keeps its OWN lower bound, carried into SQL as a joined VALUES
    # list. Collapsing them to one global minimum instead — the obvious way to
    # write this — measured four times SLOWER than the per-instrument queries
    # it replaced on the production portfolio: one holding first bought years
    # ago drags every other instrument's window back with it, and the two
    # scans then haul most of a 2M-row market_prices and a 1.4M-row candles
    # table into Ruby to discard nearly all of it. Two queries only beat
    # several hundred when they don't also read far more rows.
    sig do
      params(windows: T::Hash[String, Date], to: Date)
        .returns(T::Hash[String, T::Hash[Date, BigDecimal]])
    end
    def self.daily_closes_by_security(windows, to: Date.current)
      bounds = windows.compact
      return {} if bounds.empty?

      values = bounds.map { |security_id, from|
        ::ActiveRecord::Base.sanitize_sql_array([ "(?::uuid, ?::date)", security_id, from ])
      }.join(", ")

      out = T.let(Hash.new { |h, k| h[k] = {} }, T::Hash[String, T::Hash[Date, BigDecimal]])
      # Legacy first so candles overwrite it on shared dates.
      [
        [ "market_prices", "" ],
        [ "candles", "AND p.granularity = '1d'" ]
      ].each do |table, extra|
        sql = ::ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, to ])
          SELECT p.security_id, p.date, COALESCE(p.adjusted_close, p.close)
          FROM #{table} p
          JOIN (VALUES #{values}) AS w(security_id, from_date)
            ON w.security_id = p.security_id
          WHERE p.date >= w.from_date AND p.date <= ? #{extra}
        SQL

        ::ActiveRecord::Base.connection.select_rows(sql).each do |security_id, date, close|
          T.must(out[security_id])[date.to_date] = close.to_d
        end
      end
      out
    end

    # The newest close strictly before each instrument's own date, in one
    # DISTINCT ON query per table (candles win a shared date, as above).
    # Seeds a daily_closes_by_security window so "the last close on or before
    # day d" is answerable for every d in it, however far back that close is.
    # Returns {security_id => [date, adjusted_close]}.
    sig { params(befores: T::Hash[String, Date]).returns(T::Hash[String, [ Date, BigDecimal ]]) }
    def self.closes_before_by_security(befores)
      bounds = befores.compact
      return {} if bounds.empty?

      values = bounds.map { |security_id, before|
        ::ActiveRecord::Base.sanitize_sql_array([ "(?::uuid, ?::date)", security_id, before ])
      }.join(", ")

      picks = [
        [ "market_prices", "" ],
        [ "candles", "AND p.granularity = '1d'" ]
      ].map do |table, extra|
        sql = <<~SQL.squish
          SELECT DISTINCT ON (p.security_id) p.security_id, p.date, COALESCE(p.adjusted_close, p.close)
          FROM #{table} p
          JOIN (VALUES #{values}) AS w(security_id, before_date)
            ON w.security_id = p.security_id
          WHERE p.date < w.before_date #{extra}
          ORDER BY p.security_id, p.date DESC
        SQL
        ::ActiveRecord::Base.connection.select_rows(sql).to_h { |id, date, close| [ id, [ date.to_date, close.to_d ] ] }
      end
      legacy, candles = picks

      legacy.merge(candles) { |_id, legacy_pick, candle_pick| legacy_pick.first > candle_pick.first ? legacy_pick : candle_pick }
    end

    # One close per instrument in two DISTINCT ON queries: the newest close,
    # or with on_or_after: the first close on or after that date (a year-to-
    # date baseline). Same candles-over-legacy precedence on a shared date.
    # Returns {security_id => [date, adjusted_close]}.
    sig do
      params(security_ids: T::Array[String], on_or_after: T.nilable(Date))
        .returns(T::Hash[String, [ Date, BigDecimal ]])
    end
    def self.edge_closes_by_security(security_ids, on_or_after: nil)
      return {} if security_ids.empty?

      direction = on_or_after ? "ASC" : "DESC"
      picks = [ MarketPrice.all, Candle.daily ].map do |scope|
        scope = scope.where(security_id: security_ids)
        scope = scope.where(date: on_or_after..) if on_or_after
        scope.order(Arel.sql("security_id, date #{direction}"))
             .pluck(Arel.sql("DISTINCT ON (security_id) security_id"), :date, Arel.sql("COALESCE(adjusted_close, close)"))
             .to_h { |security_id, date, close| [ security_id, [ date, close.to_d ] ] }
      end
      legacy, candles = picks

      legacy.merge(candles) do |_id, legacy_pick, candle_pick|
        better = on_or_after ? legacy_pick.first < candle_pick.first : legacy_pick.first > candle_pick.first
        better ? legacy_pick : candle_pick
      end
    end

    # Close on `date`, falling back to the most recent close within
    # `max_staleness_days` before it (weekends/gaps). Same candles-over-legacy
    # precedence as daily_closes. Nil when nothing is close enough.
    sig { params(security: Security, date: Date, max_staleness_days: Integer).returns(T.nilable(BigDecimal)) }
    def self.close_on(security, date, max_staleness_days: 7)
      from = date - max_staleness_days
      daily_closes(security, from: from, to: date).last&.last
    end

    # Freshest price with provenance and staleness: spot quote first, then
    # the newest candle, then legacy market_prices.
    sig { params(security: Security).returns(T.nilable(Spot)) }
    def self.latest_quote(security)
      quote = InstrumentQuote.find_by(security_id: security.id)
      return Spot.new(price: quote.price.to_d, currency: quote.currency,
                      as_of: quote.as_of, source: quote.source) if quote

      candle = Candle.daily.where(security_id: security.id).order(date: :desc).first
      if candle
        return Spot.new(price: (candle.adjusted_close || candle.close).to_d,
                        currency: candle.currency, as_of: candle.date.to_time,
                        source: candle.source)
      end

      legacy = MarketPrice.where(security_id: security.id).order(date: :desc).first
      return nil unless legacy

      Spot.new(price: legacy.close.to_d, currency: "USD",
               as_of: legacy.date.to_time, source: "legacy")
    end
  end
end
