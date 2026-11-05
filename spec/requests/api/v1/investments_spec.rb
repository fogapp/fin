require "rails_helper"

RSpec.describe "Api::V1 Investment endpoints", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  shared_examples "requires authentication" do |method, path|
    it "returns 401 without a token" do
      send(method, path)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/buys" do
    include_examples "requires authentication", :get, "/api/v1/buys"

    it "returns buys summary" do
      get "/api/v1/buys", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("totals", "monthly_volume", "top_securities", "transactions")
    end

    describe "transaction windowing" do
      let!(:type) { create(:transaction_type, :purchase) }

      before do
        stub_const("Api::Render::Concerns::SerializesInvestmentTransaction::DEFAULT_TRANSACTION_LIMIT", 2)
        3.times { |i| create(:investment_transaction, transaction_type: type, trade_date: Date.current - i) }
      end

      it "caps transactions at the default limit while totals keep the full count" do
        get "/api/v1/buys", headers: auth_headers

        body = response.parsed_body
        expect(body["transactions"].length).to eq(2)
        expect(body["totals"]["count"]).to eq(3)
      end

      it "honors limit and offset params" do
        get "/api/v1/buys", params: { limit: 1, offset: 2 }, headers: auth_headers

        transactions = response.parsed_body["transactions"]
        expect(transactions.length).to eq(1)
        # Ordered newest-first, so offset 2 lands on the oldest row.
        expect(transactions.sole["trade_date"]).to eq((Date.current - 2).iso8601)
      end

      it "clamps limit to the maximum" do
        stub_const("Api::Render::Concerns::SerializesInvestmentTransaction::MAX_TRANSACTION_LIMIT", 1)

        get "/api/v1/buys", params: { limit: 999 }, headers: auth_headers
        expect(response.parsed_body["transactions"].length).to eq(1)
      end
    end

    it "is cached: repeat reads serve from cache and a write rotates the ETag" do
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      type = create(:transaction_type, :purchase)
      create(:investment_transaction, transaction_type: type)

      expect(Api::Render::Buys).to receive(:new).once.and_call_original
      get "/api/v1/buys", headers: auth_headers
      etag = response.headers["ETag"]
      expect(etag).to be_present

      # Matching ETag → 304 without recomputing (the receive(:new).once above
      # would fail if this rendered again).
      get "/api/v1/buys", headers: auth_headers.merge("If-None-Match" => etag)
      expect(response).to have_http_status(:not_modified)

      # A committed financial write rotates the DataVersion → recompute.
      create(:investment_transaction, transaction_type: type)
      expect(Api::Render::Buys).to receive(:new).once.and_call_original
      get "/api/v1/buys", headers: auth_headers.merge("If-None-Match" => etag)
      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    ensure
      Rails.cache = original
    end
  end

  describe "GET /api/v1/sells" do
    include_examples "requires authentication", :get, "/api/v1/sells"

    it "returns sells summary" do
      get "/api/v1/sells", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("totals", "monthly_volume", "monthly_gl", "transactions")
    end

    it "caps transactions at the default limit" do
      stub_const("Api::Render::Concerns::SerializesInvestmentTransaction::DEFAULT_TRANSACTION_LIMIT", 1)
      type = create(:transaction_type, :sale)
      create_list(:investment_transaction, 2, transaction_type: type)

      get "/api/v1/sells", headers: auth_headers
      body = response.parsed_body
      expect(body["transactions"].length).to eq(1)
      expect(body["totals"]["count"]).to eq(2)
    end
  end

  describe "GET /api/v1/dividends" do
    include_examples "requires authentication", :get, "/api/v1/dividends"

    it "returns dividends summary" do
      get "/api/v1/dividends", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("totals", "monthly_dividends", "top_securities", "transactions")
    end

    it "caps transactions at the default limit" do
      stub_const("Api::Render::Concerns::SerializesInvestmentTransaction::DEFAULT_TRANSACTION_LIMIT", 1)
      type = create(:transaction_type, :dividend)
      create_list(:investment_transaction, 2, transaction_type: type)

      get "/api/v1/dividends", headers: auth_headers
      body = response.parsed_body
      expect(body["transactions"].length).to eq(1)
      expect(body["totals"]["count"]).to eq(2)
    end

    it "honors the from param in the windowed totals (and keys the cache on it)" do
      type = create(:transaction_type, :dividend)
      create(:investment_transaction, transaction_type: type, trade_date: 2.years.ago.to_date, amount_usd: 100)
      create(:investment_transaction, transaction_type: type, trade_date: 1.month.ago.to_date, amount_usd: 40)

      get "/api/v1/dividends", params: { from: 6.months.ago.to_date.iso8601 }, headers: auth_headers
      expect(response.parsed_body.dig("totals", "count_12mo")).to eq(1)

      get "/api/v1/dividends", params: { from: 3.years.ago.to_date.iso8601 }, headers: auth_headers
      expect(response.parsed_body.dig("totals", "count_12mo")).to eq(2)
    end
  end

  describe "timeframe windows" do
    let(:type) { create(:transaction_type, :purchase) }

    before do
      create(:investment_transaction, transaction_type: type, trade_date: Date.new(2024, 6, 1), amount_usd: 100)
      create(:investment_transaction, transaction_type: type, trade_date: Date.new(2025, 3, 1), amount_usd: 40)
      create(:investment_transaction, transaction_type: type, trade_date: Date.new(2025, 9, 1), amount_usd: 60)
      create(:investment_transaction, transaction_type: type, trade_date: Date.new(2026, 2, 1), amount_usd: 25)
    end

    it "scopes charts, lists, and period stats to from/to while lifetime totals stay whole" do
      get "/api/v1/buys", params: { from: "2025-01-01", to: "2025-12-31" }, headers: auth_headers
      body = response.parsed_body

      expect(body["transactions"].map { |t| t["trade_date"] }).to contain_exactly("2025-03-01", "2025-09-01")
      # Gap months are zero-filled; only the window's two buys carry volume.
      expect(body["monthly_volume"].reject { |_, v| v.zero? }).to eq([ [ "2025-03-01", 40.0 ], [ "2025-09-01", 60.0 ] ])
      expect(body["monthly_volume"].first.first).to eq("2025-03-01")
      expect(body["top_securities"].sum { |s| s["total"] }).to eq(100.0)
      expect(body.dig("totals", "last_12mo")).to eq(100.0)
      expect(body.dig("totals", "count_12mo")).to eq(2)
      expect(body.dig("totals", "all_time")).to eq(225.0)
      expect(body.dig("totals", "count")).to eq(4)
    end

    it "keeps the cumulative line's running total from before the window" do
      get "/api/v1/buys", params: { from: "2025-01-01", to: "2025-12-31" }, headers: auth_headers
      points = response.parsed_body["cumulative_invested"]
      expect(points.map(&:first)).to all(be >= "2025-01-01")
      expect(points.first.last).to eq(100.0)  # the 2024 buy, carried in
      expect(points.last).to eq([ "2025-09-01", 200.0 ])
    end

    it "keys the cache on the window end" do
      get "/api/v1/buys", params: { from: "2025-01-01", to: "2025-06-30" }, headers: auth_headers
      expect(response.parsed_body.dig("totals", "count_12mo")).to eq(1)

      get "/api/v1/buys", params: { from: "2025-01-01", to: "2026-12-31" }, headers: auth_headers
      expect(response.parsed_body.dig("totals", "count_12mo")).to eq(3)
    end

    it "windows crypto activity but not the point-in-time summary" do
      crypto = create(:security, security_type: Security::CRYPTO_TYPE)
      create(:investment_transaction, transaction_type: type, security: crypto, trade_date: Date.new(2024, 6, 1), amount_usd: 500)
      create(:investment_transaction, transaction_type: type, security: crypto, trade_date: Date.new(2025, 6, 1), amount_usd: 300)

      get "/api/v1/crypto", params: { from: "2025-01-01", to: "2025-12-31" }, headers: auth_headers
      body = response.parsed_body
      expect(body["recent"].map { |t| t["trade_date"] }).to eq([ "2025-06-01" ])
      expect(body["monthly_volume"]).to eq([ [ "2025-06-01", 300.0 ] ])
      expect(body.dig("summary", "total_invested")).to eq(800.0)
    end
  end

  describe "GET /api/v1/market" do
    include_examples "requires authentication", :get, "/api/v1/market"

    it "returns the household's securities" do
      create(:security, ticker: "AAPL", watched: true)
      get "/api/v1/market", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.first).to include("ticker", "name", "display_name")
    end
  end

  describe "GET /api/v1/market/:id" do
    it "returns the security by id" do
      security = create(:security)
      get "/api/v1/market/#{security.ticker}", headers: auth_headers
      expect(response).to have_http_status(:ok)

      expect(response.parsed_body).to include("price_chart", "dividends", "recent_transactions")
    end

    it "returns the security by ticker" do
      security = create(:security, ticker: "MSFT")
      get "/api/v1/market/MSFT", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ticker"]).to eq("MSFT")
    end

    it "returns 404 for a nonexistent security" do
      get "/api/v1/market/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
