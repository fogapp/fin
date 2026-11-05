# typed: strict

module MarketData
  # Full OHLCV read API for candlestick charts, with the same
  # candles-over-legacy precedence as PriceSeries.daily_closes. Prices are
  # back-adjusted for splits: when a row carries an adjusted close, its
  # open/high/low scale by the same adjustment factor so historic candles
  # line up with the adjusted close series instead of drawing split cliffs.
  module OhlcvSeries
    extend T::Sig

    GRANULARITY_WEEKLY = "1w"

    Row = Struct.new(:date, :open, :high, :low, :close, :volume, keyword_init: true)

    # Ascending Row structs. open/high/low are nil for close-only sources
    # (CoinGecko crypto history) — callers fall back to line rendering.
    sig { params(security: Security, from: T.nilable(Date), to: Date).returns(T::Array[Row]) }
    def self.rows(security, from: nil, to: Date.current)
      merged = {}
      [ MarketPrice.where(security_id: security.id), Candle.daily.where(security_id: security.id) ].each do |scope|
        scope = scope.where(date: ..to)
        scope = scope.where(date: from..) if from
        scope.pluck(:date, :open, :high, :low, :close, :adjusted_close, :volume).each do |d, o, h, l, c, ac, v|
          merged[d] = [ o, h, l, c, ac, v ]
        end
      end

      merged.sort.map do |date, (o, h, l, c, ac, v)|
        factor = ac.present? && c.present? && c.positive? ? ac / c : 1
        Row.new(
          date:   date,
          open:   o.nil? ? nil : (o * factor).to_f,
          high:   h.nil? ? nil : (h * factor).to_f,
          low:    l.nil? ? nil : (l * factor).to_f,
          close:  (ac || c).to_f,
          volume: v&.to_i
        )
      end
    end

    # Aggregates daily rows into ISO-week candles: first open, max high,
    # min low, last close, summed volume. Weeks whose rows carry no
    # open/high/low (close-only sources) keep those fields nil.
    sig { params(rows: T::Array[Row]).returns(T::Array[Row]) }
    def self.weekly(rows)
      rows.group_by { |r| [ r.date.cwyear, r.date.cweek ] }.values.map do |week|
        last  = T.must(week.last)
        highs = week.filter_map(&:high)
        lows  = week.filter_map(&:low)
        vols  = week.filter_map(&:volume)
        Row.new(
          date:   last.date,
          open:   week.filter_map(&:open).first,
          high:   highs.max,
          low:    lows.min,
          close:  last.close,
          volume: vols.empty? ? nil : vols.sum
        )
      end
    end
  end
end
