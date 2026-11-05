# typed: strict

module MarketData
  # Batched per-security chart stats for list payloads: a ~30-point close
  # sparkline and the latest day-over-day change, computed from EOD closes
  # in two queries total (never per-row). Crypto securities carrying a spot
  # quote get their fresher 24h change from InstrumentQuote instead.
  class DailyStats
    extend T::Sig

    SPARK_DAYS = 45 # calendar window that comfortably covers 30 trading days
    SPARK_POINTS = 30

    Stat = Struct.new(:spark, :day_change_pct, :last_close, :last_date, keyword_init: true)

    sig { params(security_ids: T::Array[String]).returns(T::Hash[String, Stat]) }
    def self.call(security_ids)
      return {} if security_ids.empty?

      since  = Date.current - SPARK_DAYS
      closes = PriceSeries.daily_closes_by_security(security_ids.to_h { |sid| [ sid, since ] })
                          .transform_values { |by_date| by_date.sort.map { |date, close| [ date, close.to_f ] } }

      quote_changes = InstrumentQuote
        .where(security_id: security_ids)
        .where.not(change_pct_24h: nil)
        .pluck(:security_id, :change_pct_24h)
        .to_h

      closes.each_with_object({}) do |(sid, rows), stats|
        recent = rows.last(SPARK_POINTS)
        last   = recent.last
        prev   = recent[-2]
        change = if quote_changes.key?(sid)
          quote_changes.fetch(sid).to_f.round(2)
        elsif last && prev && prev.last.positive?
          ((last.last - prev.last) / prev.last * 100).round(2)
        end

        stats[sid] = Stat.new(
          spark:          recent.map(&:last),
          day_change_pct: change,
          last_close:     last&.last,
          last_date:      last&.first
        )
      end
    end
  end
end
