require "rails_helper"

RSpec.describe "Api::V1::Securities", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/market" do
    it "returns 401 without authentication" do
      get "/api/v1/market"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with an array of securities" do
      create(:security, ticker: "AAPL", name: "Apple Inc", watched: true)

      get "/api/v1/market", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
    end

    it "includes expected keys on each security" do
      create(:security, ticker: "AAPL", name: "Apple Inc", watched: true)

      get "/api/v1/market", headers: auth_headers
      item = response.parsed_body.first
      expect(item).to include("ticker", "name", "ytd_change_pct", "market_value", "watched")
    end

    it "returns empty array when no securities exist" do
      get "/api/v1/market", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end
  end

  describe "GET /api/v1/market/:id" do
    let!(:security) { create(:security, ticker: "MSFT", name: "Microsoft") }

    it "returns 401 without authentication" do
      get "/api/v1/market/MSFT"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns security detail by ticker" do
      get "/api/v1/market/MSFT", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["ticker"]).to eq("MSFT")
      expect(body["name"]).to eq("Microsoft")
    end

    it "includes price_chart, position, dividends, and recent_transactions" do
      get "/api/v1/market/MSFT", headers: auth_headers
      body = response.parsed_body
      expect(body).to include("price_chart", "position", "dividends", "recent_transactions")
    end

    it "reports watchlist membership for the current household" do
      get "/api/v1/market/MSFT", headers: auth_headers
      expect(response.parsed_body["watched"]).to be false

      SecurityWatch.create!(security: security, household: token.household)

      get "/api/v1/market/MSFT", headers: auth_headers
      expect(response.parsed_body["watched"]).to be true
    end

    it "returns position as nil when no snapshots exist" do
      get "/api/v1/market/MSFT", headers: auth_headers
      expect(response.parsed_body["position"]).to be_nil
    end

    it "returns position data when snapshots exist" do
      create(:position_snapshot, security: security, market_value: 5000.0, quantity: 10)

      get "/api/v1/market/MSFT", headers: auth_headers
      position = response.parsed_body["position"]
      expect(position).to include("quantity", "market_value", "cost_basis", "unrealized_gl")
    end

    it "returns 404 for unknown ticker" do
      get "/api/v1/market/UNKNOWN", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it "is case-insensitive for the ticker lookup" do
      get "/api/v1/market/msft", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ticker"]).to eq("MSFT")
    end
  end

  describe "GET /api/v1/market/search" do
    it "returns 401 without authentication" do
      get "/api/v1/market/search", params: { q: "NVDA" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns provider matches for unknown tickers" do
      results = [ { ticker: "NVDA", name: "NVIDIA Corporation", security_type: "Equity",
                    region: "United States", currency: "USD", match_score: 1.0,
                    instrument_class: "equity" } ]
      search = instance_double(Instruments::TickerSearch, call: results)
      allow(Instruments::TickerSearch).to receive(:new).and_return(search)

      get "/api/v1/market/search", params: { q: "NVDA" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["results"].size).to eq(1)
      expect(body["results"].first).to include(
        "ticker" => "NVDA", "name" => "NVIDIA Corporation", "instrument_class" => "equity"
      )
      expect(search).to have_received(:call).with("NVDA")
    end

    it "returns an empty result set when the search finds nothing" do
      allow(Instruments::TickerSearch).to receive(:new)
        .and_return(instance_double(Instruments::TickerSearch, call: []))

      get "/api/v1/market/search", params: { q: "ZZZZZZ" }, headers: auth_headers
      expect(response.parsed_body).to eq("results" => [])
    end
  end

  describe "POST /api/v1/market/watch" do
    it "returns 401 without authentication" do
      post "/api/v1/market/watch", params: { ticker: "NVDA" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates the security with the given instrument class" do
      post "/api/v1/market/watch",
           params: { ticker: "VTI", name: "Vanguard Total Stock Market ETF", instrument_class: "etf" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(Security.find_by(ticker: "VTI").instrument_class).to eq(Instruments::InstrumentClass::Etf)
    end

    it "falls back to equity for unrecognized instrument classes" do
      post "/api/v1/market/watch",
           params: { ticker: "HACK", instrument_class: "crypto" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(Security.find_by(ticker: "HACK").instrument_class).to eq(Instruments::InstrumentClass::Equity)
    end

    it "creates a new watched security and returns 200" do
      expect {
        post "/api/v1/market/watch", params: { ticker: "NVDA", name: "NVIDIA" },
             headers: auth_headers, as: :json
      }.to change(Security, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["ticker"]).to eq("NVDA")
      expect(body["watched"]).to be true
    end

    it "marks an existing security as watched" do
      security = create(:security, ticker: "TSLA", watched: false)

      post "/api/v1/market/watch", params: { ticker: "TSLA" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(security.reload.watched_by?(token.household)).to be true
    end

    it "does not create duplicate securities" do
      create(:security, ticker: "AMZN")

      expect {
        post "/api/v1/market/watch", params: { ticker: "AMZN" },
             headers: auth_headers, as: :json
      }.not_to change(Security, :count)
    end
  end

  describe "DELETE /api/v1/market/:id/unwatch" do
    let!(:security) { create(:security, ticker: "GOOG", watched: true) }

    it "returns 401 without authentication" do
      delete "/api/v1/market/GOOG/unwatch"
      expect(response).to have_http_status(:unauthorized)
    end

    it "marks security as not watched and returns 204" do
      delete "/api/v1/market/GOOG/unwatch", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(security.reload.watched_by?(token.household)).to be false
    end

    it "returns 404 for unknown ticker" do
      delete "/api/v1/market/UNKNOWN/unwatch", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/market/:id/refresh" do
    let!(:security) { create(:security, ticker: "META") }

    it "returns 401 without authentication" do
      post "/api/v1/market/META/refresh"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with a status key" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ALPHA_VANTAGE_API_KEY").and_return("test-key")
      allow_any_instance_of(SecurityOverviewSyncer).to receive(:call)
      post "/api/v1/market/META/refresh", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status")
    end

    it "returns 404 for unknown ticker" do
      post "/api/v1/market/UNKNOWN/refresh", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/market/:id/candles" do
    let!(:security) { create(:security, ticker: "NVDA") }

    it "returns 401 without authentication" do
      get "/api/v1/market/NVDA/candles"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns daily OHLCV candles with meta" do
      create(:market_price, security: security, date: Date.current - 2,
             open: 10, high: 12, low: 9, close: 11, adjusted_close: 11, volume: 500)

      get "/api/v1/market/NVDA/candles?range=1m", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("ticker" => "NVDA", "range" => "1m", "granularity" => "1d")
      expect(body["candles"].first).to include(
        "t" => (Date.current - 2).to_s, "o" => 10.0, "h" => 12.0, "l" => 9.0, "c" => 11.0, "v" => 500
      )
    end

    it "falls back to the 1y range for unknown range params" do
      get "/api/v1/market/NVDA/candles?range=bogus", headers: auth_headers
      expect(response.parsed_body["range"]).to eq("1y")
    end

    it "serves weekly granularity for 5y" do
      create(:market_price, security: security, date: Date.current - 10)

      get "/api/v1/market/NVDA/candles?range=5y", headers: auth_headers
      expect(response.parsed_body["granularity"]).to eq("1w")
    end

    it "includes the previous close and corporate-action events" do
      create(:market_price, security: security, date: Date.current - 45, close: 90, adjusted_close: 90)
      create(:market_price, security: security, date: Date.current - 2, close: 11, adjusted_close: 11)
      create(:corporate_action, security: security, ex_date: Date.current - 5, amount: 0.5)

      get "/api/v1/market/NVDA/candles?range=1m", headers: auth_headers
      body = response.parsed_body
      expect(body["prev_close"]).to eq(90.0)
      expect(body["events"]).to contain_exactly(
        a_hash_including("kind" => "dividend", "date" => (Date.current - 5).to_s, "amount" => 0.5)
      )
    end

    it "returns 404 for unknown ticker" do
      get "/api/v1/market/UNKNOWN/candles", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/market/:id/news" do
    it "returns the security's articles newest first, case-insensitive on the ticker" do
      security = create(:security, ticker: "NEWZ")
      create(:security_news_article, security: security, title: "Older", published_at: Time.zone.local(2026, 1, 1, 9, 30))
      create(:security_news_article, security: security, title: "Newer", published_at: Time.zone.local(2026, 2, 1, 16, 0),
                                     sentiment_score: 0.25)

      get "/api/v1/market/newz/news", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.map { |a| a["title"] }).to eq(%w[Newer Older])
      expect(body.first).to eq(
        "title" => "Newer", "url" => body.first["url"], "source" => "Newswire",
        "published_at" => "20260201T160000", "summary" => "Something happened in the markets.",
        "sentiment" => "Neutral", "sentiment_score" => 0.25
      )
    end
  end

  describe "GET /api/v1/market/summary" do
    it "returns 401 without authentication" do
      get "/api/v1/market/summary"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns indices, movers, and news keys" do
      get "/api/v1/market/summary", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("as_of", "indices", "movers", "news")
    end

    it "lists benchmark indices with day stats" do
      spy = create(:security, ticker: "SPY", name: "S&P 500 ETF")
      create(:market_price, security: spy, date: Date.current - 2, close: 500, adjusted_close: 500)
      create(:market_price, security: spy, date: Date.current - 1, close: 505, adjusted_close: 505)

      get "/api/v1/market/summary", headers: auth_headers
      index = response.parsed_body["indices"].find { |i| i["symbol"] == "SPY" }
      expect(index).to include("label" => "S&P 500", "close" => 505.0, "day_change_pct" => 1.0)
      expect(index["spark"]).to eq([ 500.0, 505.0 ])
    end

    it "surfaces watched securities as movers with news" do
      watched = create(:security, ticker: "AMD", watched: true)
      create(:market_price, security: watched, date: Date.current - 2, close: 100, adjusted_close: 100)
      create(:market_price, security: watched, date: Date.current - 1, close: 110, adjusted_close: 110)
      create(:security_news_article, security: watched, title: "AMD pops")

      get "/api/v1/market/summary", headers: auth_headers
      body = response.parsed_body
      expect(body["movers"]["gainers"].first).to include("ticker" => "AMD", "day_change_pct" => 10.0)
      expect(body["news"].first).to include("ticker" => "AMD", "title" => "AMD pops")
    end

    it "excludes untracked securities from movers" do
      untracked = create(:security, ticker: "XYZ")
      create(:market_price, security: untracked, date: Date.current - 2, close: 100, adjusted_close: 100)
      create(:market_price, security: untracked, date: Date.current - 1, close: 150, adjusted_close: 150)

      get "/api/v1/market/summary", headers: auth_headers
      tickers = response.parsed_body["movers"]["gainers"].map { |m| m["ticker"] }
      expect(tickers).not_to include("XYZ")
    end
  end

  describe "GET /api/v1/market index day stats" do
    it "includes day_change_pct and spark on each row" do
      security = create(:security, ticker: "AAPL", watched: true)
      create(:market_price, security: security, date: Date.current - 2, close: 200, adjusted_close: 200)
      create(:market_price, security: security, date: Date.current - 1, close: 202, adjusted_close: 202)

      get "/api/v1/market", headers: auth_headers
      row = response.parsed_body.find { |s| s["ticker"] == "AAPL" }
      expect(row["day_change_pct"]).to eq(1.0)
      expect(row["spark"]).to eq([ 200.0, 202.0 ])
    end
  end
end
