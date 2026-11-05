require "rails_helper"

RSpec.describe "Api::V1::Benchmarks", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/benchmarks" do
    it "returns 401 without authentication" do
      get "/api/v1/benchmarks"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the curated benchmark metadata list" do
      get "/api/v1/benchmarks", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to be_an(Array)
      symbols = body.map { |b| b["symbol"] }
      expect(symbols).to include("SPY", "QQQ")
    end
  end

  describe "GET /api/v1/benchmarks/:symbol" do
    it "returns prices for a curated benchmark" do
      sec = create(:security, ticker: "SPY")
      create(:market_price, security: sec, date: Date.new(2026, 1, 1), close: 480.0)
      create(:market_price, security: sec, date: Date.new(2026, 1, 2), close: 482.0)

      get "/api/v1/benchmarks/SPY", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["symbol"]).to eq("SPY")
      expect(body["label"]).to  eq("S&P 500")
      expect(body["prices"].length).to eq(2)
      expect(body["syncing"]).to be false
    end

    it "creates no Security for an unknown ticker and returns an empty payload" do
      ENV["ALPHA_VANTAGE_API_KEY"] = "x"
      expect {
        get "/api/v1/benchmarks/UNKNOWN", headers: auth_headers
      }.not_to change(Security, :count)
      expect(SyncSecurityPricesJob).not_to have_been_enqueued

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["symbol"]).to eq("UNKNOWN")
      expect(body["prices"]).to eq([])
      expect(body["syncing"]).to be false
    ensure
      ENV.delete("ALPHA_VANTAGE_API_KEY")
    end

    it "enqueues a price sync for a known security that has no prices yet" do
      ENV["ALPHA_VANTAGE_API_KEY"] = "x"
      create(:security, ticker: "SPY", instrument_class: "etf")

      expect {
        get "/api/v1/benchmarks/SPY", headers: auth_headers
      }.to have_enqueued_job(SyncSecurityPricesJob)

      expect(response.parsed_body["syncing"]).to be true
    ensure
      ENV.delete("ALPHA_VANTAGE_API_KEY")
    end

    it "uses the ticker as the label when the symbol is not curated" do
      sec = create(:security, ticker: "VTI")
      create(:market_price, security: sec, date: Date.current, close: 220.0)

      get "/api/v1/benchmarks/VTI", headers: auth_headers
      expect(response.parsed_body["label"]).to eq("VTI")
    end

    it "uppercases the requested symbol" do
      sec = create(:security, ticker: "QQQ")
      create(:market_price, security: sec, date: Date.current, close: 400.0)

      get "/api/v1/benchmarks/qqq", headers: auth_headers
      expect(response.parsed_body["symbol"]).to eq("QQQ")
      expect(response.parsed_body["label"]).to  eq("NASDAQ-100")
    end
  end
end
