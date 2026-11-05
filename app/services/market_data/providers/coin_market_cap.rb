# typed: strict

module MarketData
  module Providers
    # Crypto spot quotes (4-hourly cadence via SyncCryptoPricesJob →
    # CoinMarketCap::Syncer). Each quote writes instrument_quotes plus a
    # same-day candle so daily history accrues even between CoinGecko syncs.
    class CoinMarketCap
      extend T::Sig

      SOURCE = T.let(Provider::CoinMarketCap.serialize, String)

      # One spot observation: quote row + today's candle + legacy row.
      sig { params(security: Security, price: T.untyped, now: ActiveSupport::TimeWithZone).void }
      def self.write_quote!(security, price, now: Time.current)
        InstrumentQuote.upsert(
          { security_id: security.id, price: price, currency: "USD",
            source: SOURCE, as_of: now, created_at: now, updated_at: now },
          unique_by: :security_id
        )
        CandleWriter.write!(security, [ { date: Date.current, close: price } ],
                            source: SOURCE, adjusted: false, now: now)
      end
    end
  end
end
