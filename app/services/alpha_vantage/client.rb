# typed: strict

module AlphaVantage
  class Error < StandardError; end
  class RateLimitError < Error; end
  class MissingKeyError < Error; end

  class Client
    extend T::Sig

    BASE_URL = T.let("https://www.alphavantage.co/query".freeze, String)

    sig { params(api_key: T.nilable(String)).void }
    def initialize(api_key: nil)
      key = api_key || AlphaVantage.api_key
      raise MissingKeyError, "Alpha Vantage API key is not configured" if key.blank?
      @api_key = T.let(key, String)
    end

    # Returns up to `limit` news articles for the given ticker.
    # Each article: { title:, url:, source:, published_at:, summary:, sentiment: }
    sig { params(symbol: String, limit: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def news_sentiment(symbol, limit: 20)
      raw = get(function: "NEWS_SENTIMENT", tickers: symbol, limit: limit, sort: "LATEST")
      feed = raw["feed"]
      return [] unless feed.is_a?(Array)

      feed.map do |item|
        ticker_sentiment = item["ticker_sentiment"]&.find { |ts| ts["ticker"]&.upcase == symbol.upcase }
        {
          title:        item["title"],
          url:          item["url"],
          source:       item["source"],
          published_at: item["time_published"],
          summary:      item["summary"],
          sentiment:    ticker_sentiment&.dig("ticker_sentiment_label"),
          sentiment_score: ticker_sentiment&.dig("ticker_sentiment_score")&.to_f
        }
      end
    end

    # Returns the raw OVERVIEW hash for a ticker, or nil if the symbol is unknown.
    sig { params(symbol: String).returns(T.nilable(T::Hash[String, T.untyped])) }
    def company_overview(symbol)
      raw = get(function: "OVERVIEW", symbol: symbol)
      return nil if raw["Symbol"].blank?
      raw
    end

    # Symbol search for a keyword/ticker fragment. Returns bestMatches as
    # { ticker:, name:, security_type:, region:, currency:, match_score: }.
    sig { params(keywords: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def symbol_search(keywords)
      raw = get(function: "SYMBOL_SEARCH", keywords: keywords)
      matches = raw["bestMatches"]
      return [] unless matches.is_a?(Array)

      matches.map do |m|
        {
          ticker:        m["1. symbol"],
          name:          m["2. name"],
          security_type: m["3. type"],
          region:        m["4. region"],
          currency:      m["8. currency"],
          match_score:   m["9. matchScore"].to_f
        }
      end
    end

    # Returns an array of { date:, open:, high:, low:, close:, volume: } hashes
    # for the given ticker symbol. `outputsize` is "compact" (last 100 days) or
    # "full" (20+ years).
    sig { params(symbol: String, outputsize: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def daily_time_series(symbol, outputsize: "compact")
      raw = get(function: "TIME_SERIES_DAILY", symbol: symbol, outputsize: outputsize)
      series = raw["Time Series (Daily)"]
      unless series.is_a?(Hash)
        # Rate limits / API errors already raised inside get.
        raise Error, "Unexpected Alpha Vantage response for #{symbol}: #{raw.inspect[0, 200]}"
      end

      series.map do |date_str, row|
        {
          date:   Date.parse(date_str),
          open:   BigDecimal(row["1. open"]),
          high:   BigDecimal(row["2. high"]),
          low:    BigDecimal(row["3. low"]),
          close:  BigDecimal(row["4. close"]),
          volume: row["5. volume"].to_i
        }
      end
    end

    # Split/dividend-adjusted daily series. Each row additionally carries
    # adjusted_close, dividend_amount, and split_coefficient.
    sig { params(symbol: String, outputsize: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def daily_time_series_adjusted(symbol, outputsize: "compact")
      raw = get(function: "TIME_SERIES_DAILY_ADJUSTED", symbol: symbol, outputsize: outputsize)
      series = raw["Time Series (Daily)"]
      unless series.is_a?(Hash)
        # Rate limits / API errors already raised inside get.
        raise Error, "Unexpected Alpha Vantage response for #{symbol}: #{raw.inspect[0, 200]}"
      end

      series.map do |date_str, row|
        {
          date:              Date.parse(date_str),
          open:              BigDecimal(row["1. open"]),
          high:              BigDecimal(row["2. high"]),
          low:               BigDecimal(row["3. low"]),
          close:             BigDecimal(row["4. close"]),
          adjusted_close:    BigDecimal(row["5. adjusted close"]),
          volume:            row["6. volume"].to_i,
          dividend_amount:   BigDecimal(row["7. dividend amount"]),
          split_coefficient: BigDecimal(row["8. split coefficient"])
        }
      end
    end

    # Current exchange rate, e.g. fx_rate("EUR", "USD") => BigDecimal.
    sig { params(from: String, to: String).returns(T.nilable(BigDecimal)) }
    def fx_rate(from, to = "USD")
      raw = get(function: "CURRENCY_EXCHANGE_RATE", from_currency: from, to_currency: to)
      rate = raw.dig("Realtime Currency Exchange Rate", "5. Exchange Rate")
      rate ? BigDecimal(rate) : nil
    end

    private

    sig { params(params: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def get(params)
      uri = URI(BASE_URL)
      uri.query = URI.encode_www_form(params.merge(apikey: @api_key))
      body = HttpJson.request(:get, uri, error: Error, rate_limit_error: RateLimitError, label: "Alpha Vantage HTTP")
      check_error!(body) if body.is_a?(Hash)
      body
    end

    # Alpha Vantage returns 200 OK with an error message in the body. Known
    # keys: "Error Message", "Note" (rate limit), "Information" (rate limit on
    # the free tier). Checked on EVERY response — the endpoints that returned
    # nil/[] without looking (fx_rate, company_overview, news_sentiment) were
    # reporting rate limits as "no data", so FX sync logged stale rates as
    # success.
    sig { params(body: T::Hash[String, T.untyped]).void }
    def check_error!(body)
      if body["Error Message"].present?
        raise Error, "Alpha Vantage error: #{body['Error Message']}"
      elsif body["Note"].present?
        raise RateLimitError, "Alpha Vantage rate limit: #{body['Note']}"
      elsif body["Information"].present?
        raise RateLimitError, "Alpha Vantage rate limit: #{body['Information']}"
      end
    end
  end
end
