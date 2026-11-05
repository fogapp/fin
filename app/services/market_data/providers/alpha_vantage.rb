# typed: strict

module MarketData
  module Providers
    # Equities/ETFs/mutual funds: split- and dividend-adjusted daily candles,
    # with corporate actions extracted from the adjusted series.
    class AlphaVantage
      extend T::Sig

      sig { void }
      def initialize
        @client = T.let(::AlphaVantage::Client.new, T.untyped)
      end

      # Candle/action source column is an open string vocabulary at the DB
      # boundary — derive it from the enum so the two can never drift.
      SOURCE = T.let(Provider::AlphaVantage.serialize, String)

      # Fetches candles and upserts candles + corporate_actions. Returns the
      # number of candle rows written.
      sig { params(security: Security, link: InstrumentDataLink, full: T::Boolean).returns(Integer) }
      def sync_candles(security, link, full: false)
        rows = @client.daily_time_series_adjusted(
          T.must(security.ticker),
          outputsize: full ? "full" : "compact"
        )
        return 0 if rows.empty?

        now = Time.current
        CandleWriter.write_corporate_actions!(security, rows, source: SOURCE, now: now)
        CandleWriter.write!(security, rows, source: SOURCE, now: now)
      end

      # Raw closes since `from`, without storing anything — for comparing
      # against another source. Raw daily compact (~100 sessions) is free-tier
      # friendly; adjusted daily is not.
      sig { params(security: Security, from: Date).returns(T::Hash[Date, BigDecimal]) }
      def fetch_closes(security, from:)
        @client.daily_time_series(T.must(security.ticker), outputsize: "compact")
               .select { |row| row[:date] >= from }
               .to_h { |row| [ row[:date], row[:close].to_d ] }
      end
    end
  end
end
