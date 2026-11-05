# typed: strict

module MarketData
  module Providers
    # Tiingo serves candles for two instrument shapes: equities/ETFs/mutual
    # funds get the split- and dividend-adjusted daily series (with corporate
    # actions extracted, mirroring the Alpha Vantage provider), and crypto
    # gets full OHLCV from the crypto endpoint — richer than keyless
    # CoinGecko, which is close-only and capped at a trailing year.
    class Tiingo
      extend T::Sig

      # Candle/action source column is an open string vocabulary at the DB
      # boundary — derive it from the enum so the two can never drift.
      SOURCE = T.let(Provider::Tiingo.serialize, String)

      # Tiingo's daily endpoint returns the whole listing history when no
      # startDate is given; compact syncs only need the recent window.
      COMPACT_WINDOW = T.let(45, Integer)

      # Tiingo crypto tickers are <base><quote> pairs; we always price in USD.
      sig { params(security: Security).returns(String) }
      def self.crypto_pair(security)
        "#{T.must(security.ticker).downcase}usd"
      end

      sig { void }
      def initialize
        @client = T.let(::Tiingo::Client.new, ::Tiingo::Client)
      end

      # Fetches candles and upserts candles (+ corporate_actions for
      # non-crypto). Returns the number of candle rows written.
      sig { params(security: Security, link: InstrumentDataLink, full: T::Boolean).returns(Integer) }
      def sync_candles(security, link, full: false)
        start = full ? nil : COMPACT_WINDOW.days.ago.to_date
        now = Time.current

        if crypto?(security)
          pair = link.provider_ref.presence || resolve_pair!(security, link)
          CandleWriter.write!(security, @client.crypto_prices(pair, start_date: start),
                              source: SOURCE, adjusted: false, now: now)
        else
          rows = @client.daily_prices(T.must(security.ticker), start_date: start)
          CandleWriter.write_corporate_actions!(security, rows, source: SOURCE, now: now)
          CandleWriter.write!(security, rows, source: SOURCE, now: now)
        end
      end

      # Raw closes since `from`, without storing anything — for comparing
      # against another source.
      sig { params(security: Security, from: Date).returns(T::Hash[Date, BigDecimal]) }
      def fetch_closes(security, from:)
        rows = if crypto?(security)
          @client.crypto_prices(self.class.crypto_pair(security), start_date: from)
        else
          @client.daily_prices(T.must(security.ticker), start_date: from)
        end
        rows.to_h { |row| [ row[:date], row[:close].to_d ] }
      end

      private

      sig { params(security: Security).returns(T::Boolean) }
      def crypto?(security)
        security.instrument_class == Instruments::InstrumentClass::Crypto
      end

      sig { params(security: Security, link: InstrumentDataLink).returns(String) }
      def resolve_pair!(security, link)
        pair = self.class.crypto_pair(security)
        link.update!(provider_ref: pair)
        pair
      end
    end
  end
end
