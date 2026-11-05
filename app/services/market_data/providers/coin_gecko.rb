# typed: strict

module MarketData
  module Providers
    # Crypto daily history from a crypto-native source. Resolves and caches
    # the CoinGecko id as an instrument identifier on first sync.
    class CoinGecko
      extend T::Sig

      SOURCE = T.let(Provider::CoinGecko.serialize, String)

      sig { void }
      def initialize
        @client = T.let(::CoinGecko::Client.new, ::CoinGecko::Client)
      end

      sig { params(security: Security, link: InstrumentDataLink, full: T::Boolean).returns(Integer) }
      def sync_candles(security, link, full: false)
        coin_id = link.provider_ref.presence || resolve_coin_id!(security, link)
        return 0 if coin_id.blank?

        CandleWriter.write!(security, fetch_history(coin_id, full: full), source: SOURCE, adjusted: false)
      end

      # Closes since `from`, without storing anything — for comparing against
      # another source. Uses the cached CoinGecko id when there is one.
      sig { params(security: Security, from: Date).returns(T::Hash[Date, BigDecimal]) }
      def fetch_closes(security, from:)
        coin_id = InstrumentIdentifier.find_by(security_id: security.id, scheme: "coingecko_id")&.value ||
                  @client.coin_id_for(T.must(security.ticker))
        return {} if coin_id.blank?

        days = [ (Date.current - from).to_i, 1 ].max
        @client.daily_history(coin_id, days: days)
               .select { |row| row[:date] >= from && row[:close] }
               .to_h { |row| [ row[:date], row[:close].to_d ] }
      end

      private

      # Public (keyless) CoinGecko rejects days="max" with error 10012 —
      # historical data is capped at the trailing 365 days. Take what the
      # tier allows rather than failing the whole candle backfill.
      sig { params(coin_id: String, full: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def fetch_history(coin_id, full:)
        @client.daily_history(coin_id, days: full ? "max" : 30)
      rescue ::CoinGecko::Client::Error => e
        raise unless full && e.message.include?("10012")

        @client.daily_history(coin_id, days: 365)
      end

      sig { params(security: Security, link: InstrumentDataLink).returns(T.nilable(String)) }
      def resolve_coin_id!(security, link)
        coin_id = @client.coin_id_for(T.must(security.ticker))
        if coin_id.present?
          link.update!(provider_ref: coin_id)
          Instruments::Resolver.register!(security, "coingecko_id" => coin_id)
        end
        coin_id
      end
    end
  end
end
