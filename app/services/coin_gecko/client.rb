# typed: strict

module CoinGecko
  # Minimal CoinGecko client for crypto daily history and id resolution.
  # Free tier, no API key required (an optional demo key raises the rate
  # limit via COINGECKO_API_KEY).
  class Client
    extend T::Sig

    class Error < StandardError; end
    class RateLimitError < Error; end

    BASE_URL = "https://api.coingecko.com/api/v3"

    # symbol (e.g. "BTC") → coingecko id (e.g. "bitcoin"), preferring the
    # highest-ranked coin when symbols collide.
    sig { params(symbol: String).returns(T.nilable(String)) }
    def coin_id_for(symbol)
      raw = get("/search", query: symbol)
      coins = Array(raw["coins"]).select { |c| c["symbol"].to_s.casecmp?(symbol) }
      coins.min_by { |c| c["market_cap_rank"] || Float::INFINITY }&.fetch("id", nil)
    end

    # Daily close history: [{date:, close:}] in USD. days: 1..365 or "max".
    sig { params(coin_id: String, days: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def daily_history(coin_id, days: 365)
      raw = get("/coins/#{coin_id}/market_chart",
                vs_currency: "usd", days: days.to_s, interval: "daily")
      Array(raw["prices"]).map do |(ts_ms, price)|
        { date: Time.at(ts_ms / 1000).utc.to_date, close: BigDecimal(price.to_s) }
      end.uniq { |row| row[:date] }
    end

    private

    sig { params(path: String, params: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      key = ENV["COINGECKO_API_KEY"]
      params = params.merge(x_cg_demo_api_key: key) if key.present?
      uri.query = URI.encode_www_form(params)
      HttpJson.request(:get, uri, error: Error, rate_limit_error: RateLimitError, label: "CoinGecko HTTP")
    end
  end
end
