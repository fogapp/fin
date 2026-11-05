# typed: strict

module CoinMarketCap
  class Client
    extend T::Sig

    BASE_URL = T.let("https://pro-api.coinmarketcap.com".freeze, String)

    sig { params(api_key: T.nilable(String)).void }
    def initialize(api_key: nil)
      key = api_key || CoinMarketCap.api_key
      raise MissingKeyError, "CoinMarketCap API key is not configured" if key.blank?
      @api_key = T.let(key, String)
    end

    # Returns { "BTC" => 50000.0 } — price only.
    sig { params(symbols: T.untyped).returns(T.untyped) }
    def quotes(symbols)
      quote_data(symbols).transform_values { |d| d[:price] }
    end

    # Returns { "BTC" => { price: 50000.0, slug: "bitcoin" } }.
    # Unrecognised symbols are silently omitted from the result.
    sig { params(symbols: T.untyped).returns(T.untyped) }
    def quote_data(symbols)
      return {} if symbols.blank?

      # skip_invalid: one unrecognized symbol used to 400 the whole batch,
      # zeroing prices for every crypto account and watchlist entry.
      raw = get("/v2/cryptocurrency/quotes/latest",
                symbol: symbols.join(","), convert: "USD", skip_invalid: "true")
      data = raw["data"] || {}

      data.each_with_object({}) do |(symbol, entries), result|
        entry = Array(entries).first
        price = entry&.dig("quote", "USD", "price")
        next unless price

        result[symbol.upcase] = { price: price.to_f, slug: entry["slug"] }
      end
    end

    private

    sig { params(path: T.untyped, params: T::Enumerable[Object]).returns(T.untyped) }
    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params)

      HttpJson.request(:get, uri, error: Error, rate_limit_error: RateLimitError, label: "CoinMarketCap",
                                  headers: { "X-CMC_PRO_API_KEY" => @api_key, "Accept" => "application/json" },
                                  detail: ->(response) { response.json_object.dig("status", "error_message") })
    end
  end
end
