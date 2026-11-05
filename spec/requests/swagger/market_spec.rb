require "swagger_helper"

RSpec.describe "Market", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  path "/api/v1/market" do
    get "Held and watched securities with prices" do
      tags "Securities"
      produces "application/json"
      description "Securities this household has traded, holds, watches, or uses as a benchmark."

      response "200", "securities listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/SecuritySummary" }
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/market/summary" do
    get "Market overview: benchmark indices, movers and news" do
      tags "Securities"
      produces "application/json"

      response "200", "market summary" do
        schema "$ref" => "#/components/schemas/MarketSummaryData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/market/search" do
    get "Search tickers to watch" do
      tags "Securities"
      produces "application/json"
      parameter name: :q, in: :query, type: :string, required: true

      response "200", "search results" do
        schema "$ref" => "#/components/schemas/TickerSearchResults"
        let(:q) { "tesla" }
        before do
          allow(::AlphaVantage).to receive(:configured?).and_return(true)
          allow_any_instance_of(AlphaVantage::Client).to receive(:symbol_search).and_return(
            [ { ticker: "TSLA", name: "Tesla Inc.", security_type: "Equity", region: "United States",
                currency: "USD", match_score: 1.0 } ]
          )
        end
        run_test!
      end
    end
  end

  path "/api/v1/market/watch" do
    post "Watch a security" do
      tags "Securities"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          ticker:           { type: :string },
          name:             { type: :string },
          instrument_class: { type: :string, enum: %w[equity etf mutual_fund], description: "Defaults to equity" }
        },
        required: %w[ticker]
      }

      response "200", "security watched" do
        schema "$ref" => "#/components/schemas/SecurityWatchResult"
        let(:body) { { ticker: "MSFT", name: "Microsoft" } }
        run_test!
      end
    end
  end

  path "/api/v1/market/{id}" do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: "Ticker symbol"

    get "A security's price, position, dividends and fundamentals" do
      tags "Securities"
      produces "application/json"

      response "200", "security found" do
        schema "$ref" => "#/components/schemas/SecurityDetail"
        let(:id) { wealth.aapl.ticker }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { "NOPE" }
        run_test!
      end
    end
  end

  path "/api/v1/market/{id}/candles" do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: "Ticker symbol"

    get "OHLCV candles and corporate actions for a chart range" do
      tags "Securities"
      produces "application/json"
      parameter name: :range, in: :query, required: false,
                schema: { type: :string, enum: %w[1m 3m 6m ytd 1y 5y max] },
                description: "Default 1y; 5y and max are weekly"

      response "200", "candles" do
        schema "$ref" => "#/components/schemas/CandleData"
        let(:id)    { wealth.aapl.ticker }
        let(:range) { "max" }
        run_test!
      end
    end
  end

  path "/api/v1/market/{id}/news" do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: "Ticker symbol"

    get "Recent news for a security" do
      tags "Securities"
      produces "application/json"

      response "200", "news articles" do
        schema type: :array, items: { "$ref" => "#/components/schemas/NewsArticle" }
        let(:id) { wealth.aapl.ticker }
        run_test!
      end
    end
  end

  path "/api/v1/market/{id}/unwatch" do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: "Ticker symbol"

    delete "Unwatch a security" do
      tags "Securities"

      response "204", "security unwatched" do
        let(:id) { wealth.vti.ticker }
        run_test!
      end
    end
  end

  path "/api/v1/market/{id}/refresh" do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: "Ticker symbol"

    post "Refresh a security's prices and overview in the background" do
      tags "Securities"
      produces "application/json"

      response "200", "refresh enqueued" do
        schema "$ref" => "#/components/schemas/SecurityRefreshResult"
        let(:id) { wealth.aapl.ticker }
        before { allow(::AlphaVantage).to receive(:configured?).and_return(true) }
        run_test!
      end

      response "422", "no market data provider configured" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { wealth.aapl.ticker }
        before do
          allow(::AlphaVantage).to receive(:configured?).and_return(false)
          allow(MarketData::Router).to receive(:available_for?).and_return(false)
        end
        run_test!
      end
    end
  end

  path "/api/v1/benchmarks" do
    get "Benchmark indices available for comparison" do
      tags "Securities"
      produces "application/json"

      response "200", "benchmarks" do
        schema type: :array, items: { "$ref" => "#/components/schemas/BenchmarkMeta" }
        run_test!
      end
    end
  end

  path "/api/v1/benchmarks/{symbol}" do
    parameter name: :symbol, in: :path, schema: { type: :string }, required: true

    get "A benchmark's daily closes" do
      tags "Securities"
      produces "application/json"
      description "`syncing` is true when no prices are stored yet and a sync was just enqueued."

      response "200", "benchmark prices" do
        schema "$ref" => "#/components/schemas/BenchmarkEntry"
        let(:symbol) { wealth.spy.ticker }
        run_test!
      end

      response "400", "invalid ticker" do
        schema "$ref" => "#/components/schemas/Error"
        let(:symbol) { "bad_ticker" }
        run_test!
      end
    end
  end
end
