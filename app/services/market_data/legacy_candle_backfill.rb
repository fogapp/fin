# typed: strict

module MarketData
  # Stage 2 of the price consolidation (docs/price-consolidation.md): copy
  # every market_prices row the candle store doesn't cover yet into daily
  # candles, so market_prices can stop being written and then be dropped.
  #
  # Idempotent and resumable: each batch inserts only dates with no candle
  # (ON CONFLICT DO NOTHING against the unique (security, granularity, date)
  # index), so a rerun — or a run interrupted halfway — picks up where it
  # left off. Existing candles always win; legacy rows only fill gaps, the
  # same precedence PriceSeries reads with, so charts don't change.
  module LegacyCandleBackfill
    extend T::Sig

    SOURCE = "legacy_market_prices"
    BATCH_SECURITIES = 100

    # Returns the number of candle rows inserted.
    sig { params(log: T.nilable(T.proc.params(message: String).void)).returns(Integer) }
    def self.run(log: nil)
      inserted = 0
      security_ids = MarketPrice.distinct.order(:security_id).pluck(:security_id)
      security_ids.each_slice(BATCH_SECURITIES).with_index(1) do |batch, index|
        count = ::ActiveRecord::Base.connection.exec_update(insert_sql(batch))
        inserted += count
        log&.call("batch #{index}: #{batch.size} securities, #{count} candles inserted")
      end
      inserted
    end

    # market_prices rows (with a close) that still have no daily candle.
    # Zero means stage 2 can proceed.
    sig { returns(Integer) }
    def self.uncovered_count
      MarketPrice.where.not(close: nil)
                 .where("NOT EXISTS (SELECT 1 FROM candles c WHERE c.security_id = market_prices.security_id " \
                        "AND c.granularity = ? AND c.date = market_prices.date)", Candle::GRANULARITY_DAILY)
                 .count
    end

    sig { params(security_ids: T::Array[String]).returns(String) }
    def self.insert_sql(security_ids)
      ::ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, Candle::GRANULARITY_DAILY, SOURCE, security_ids ])
        INSERT INTO candles (security_id, date, granularity, open, high, low, close, adjusted_close,
                             volume, currency, source, created_at, updated_at)
        SELECT mp.security_id, mp.date, ?, mp.open, mp.high, mp.low, mp.close, mp.adjusted_close,
               mp.volume, 'USD', ?, NOW(), NOW()
        FROM market_prices mp
        WHERE mp.security_id IN (?) AND mp.close IS NOT NULL
        ON CONFLICT (security_id, granularity, date) DO NOTHING
      SQL
    end
    private_class_method :insert_sql
  end
end
