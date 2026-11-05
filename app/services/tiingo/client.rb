# typed: strict

module Tiingo
  class Client
    extend T::Sig

    BASE_URL = T.let("https://api.tiingo.com".freeze, String)

    sig { params(api_key: T.nilable(String)).void }
    def initialize(api_key: nil)
      key = api_key || Tiingo.api_key
      raise MissingKeyError, "Tiingo API key is not configured" if key.blank?
      @api_key = T.let(key, String)
    end

    # Authenticated no-op probe for the Settings test-connection button —
    # costs no symbol quota.
    sig { returns(T::Boolean) }
    def test_connection
      raw = get("/api/test")
      raw.is_a?(Hash) && raw["message"].to_s.include?("success")
    end

    # Split/dividend-adjusted daily series for equities/ETFs/mutual funds.
    # Returns rows shaped like AlphaVantage::Client#daily_time_series_adjusted
    # so provider code stays interchangeable: { date:, open:, high:, low:,
    # close:, adjusted_close:, volume:, dividend_amount:, split_coefficient: }.
    sig { params(symbol: String, start_date: T.nilable(Date)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def daily_prices(symbol, start_date: nil)
      params = {}
      params[:startDate] = start_date.iso8601 if start_date
      raw = get("/tiingo/daily/#{symbol.downcase}/prices", params)
      raise Error, "Unexpected Tiingo response for #{symbol}: #{raw.inspect[0, 200]}" unless raw.is_a?(Array)

      raw.map do |row|
        {
          date:              Date.parse(row.fetch("date")),
          open:              decimal(row["open"]),
          high:              decimal(row["high"]),
          low:               decimal(row["low"]),
          close:             decimal(row["close"]),
          adjusted_close:    decimal(row["adjClose"]),
          volume:            row["volume"].to_i,
          dividend_amount:   decimal(row["divCash"]),
          split_coefficient: decimal(row["splitFactor"])
        }
      end
    end

    # Daily OHLCV for a crypto pair (e.g. "btcusd"). Crypto has no corporate
    # actions, so close doubles as adjusted_close.
    sig { params(pair: String, start_date: T.nilable(Date)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def crypto_prices(pair, start_date: nil)
      params = { tickers: pair.downcase, resampleFreq: "1day" }
      params[:startDate] = start_date.iso8601 if start_date
      raw = get("/tiingo/crypto/prices", params)
      raise Error, "Unexpected Tiingo crypto response for #{pair}: #{raw.inspect[0, 200]}" unless raw.is_a?(Array)

      rows = raw.first&.fetch("priceData", nil)
      return [] unless rows.is_a?(Array)

      rows.map do |row|
        {
          date:   Date.parse(row.fetch("date")),
          open:   decimal(row["open"]),
          high:   decimal(row["high"]),
          low:    decimal(row["low"]),
          close:  decimal(row["close"]),
          volume: row["volume"].to_i
        }
      end
    end

    private

    sig { params(value: T.untyped).returns(T.nilable(BigDecimal)) }
    def decimal(value)
      value.nil? ? nil : BigDecimal(value.to_s)
    end

    sig { params(path: String, params: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      # Tiingo explains auth failures in "detail" ("Invalid token.").
      HttpJson.request(:get, uri, error: Error, rate_limit_error: RateLimitError, label: "Tiingo HTTP",
                                  headers: { "Authorization" => "Token #{@api_key}", "Content-Type" => "application/json" },
                                  detail: ->(response) { response.json_object["detail"] })
    end
  end
end
