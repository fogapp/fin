require "rails_helper"

RSpec.describe "Api::V1::Portfolio", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/portfolio/performance" do
    it "returns 401 without authentication" do
      get "/api/v1/portfolio/performance"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns a null payload with no portfolio history" do
      get "/api/v1/portfolio/performance", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("from", "to", "twr_pct" => nil, "xirr_pct" => nil)
    end

    it "returns 400 for malformed dates" do
      get "/api/v1/portfolio/performance?from=nonsense", headers: auth_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "computes TWR and XIRR from ledger positions and closes" do
      security = create(:security, ticker: "GRW")
      account  = create(:account)
      buy_date = Date.current - 364

      create(:investment_transaction,
             account: account, security: security,
             transaction_type: create(:transaction_type, :purchase),
             trade_date: buy_date, quantity: 10, price_usd: 100,
             amount_usd: 1000, cost_usd: 1000)

      # Weekly closes climbing 100 → 130 across the year.
      (0..52).each do |week|
        close = (100 + 30.0 * week / 52).round(6)
        create(:market_price, security: security, date: buy_date + week * 7,
               close: close, adjusted_close: close, open: close, high: close, low: close)
      end

      get "/api/v1/portfolio/performance?from=#{buy_date}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["start_value"]).to eq(1000.0)
      expect(body["end_value"]).to eq(1300.0)
      expect(body["twr_pct"]).to eq(30.0)
      expect(body["xirr_pct"]).to be_within(2.0).of(30.0)
    end

    it "suppresses XIRR for windows too short to annualize" do
      security = create(:security, ticker: "SHRT")
      account  = create(:account)
      buy_date = Date.current - 30

      create(:investment_transaction,
             account: account, security: security,
             transaction_type: create(:transaction_type, :purchase),
             trade_date: buy_date, quantity: 10, price_usd: 100,
             amount_usd: 1000, cost_usd: 1000)
      [ 0, 15, 30 ].each do |i|
        create(:market_price, security: security, date: buy_date + i,
               close: 100 + i, adjusted_close: 100 + i)
      end

      get "/api/v1/portfolio/performance?from=#{buy_date}", headers: auth_headers
      body = response.parsed_body
      expect(body["twr_pct"]).to eq(30.0)
      expect(body["xirr_pct"]).to be_nil
    end
  end

  describe "GET /api/v1/portfolio" do
    it "returns 401 without authentication" do
      get "/api/v1/portfolio"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with the expected top-level keys" do
      get "/api/v1/portfolio", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "as_of_date", "summary", "by_asset_class", "portfolio_history", "positions"
      )
    end

    it "returns empty positions array when no snapshots exist" do
      get "/api/v1/portfolio", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["positions"]).to eq([])
    end

    it "returns summary with expected keys" do
      get "/api/v1/portfolio", headers: auth_headers
      summary = response.parsed_body["summary"]
      expect(summary).to include(
        "total_value", "total_cost_basis", "unrealized_gl", "est_annual_income"
      )
    end

    it "returns positions populated from snapshots" do
      security = create(:security)
      create(:position_snapshot, security: security,
             market_value: 5000.0, cost_basis: 4000.0, quantity: 50, price: 100.0)

      get "/api/v1/portfolio", headers: auth_headers
      expect(response).to have_http_status(:ok)
      positions = response.parsed_body["positions"]
      expect(positions.length).to eq(1)
      expect(positions.first).to include(
        "security_ticker", "security_name", "market_value", "cost_basis",
        "unrealized_gl", "quantity", "price"
      )
    end

    it "sums positions across accounts for the same security" do
      security = create(:security)
      create(:position_snapshot, security: security, market_value: 3000.0, cost_basis: 2500.0, quantity: 30)
      create(:position_snapshot, security: security, market_value: 2000.0, cost_basis: 1500.0, quantity: 20)

      get "/api/v1/portfolio", headers: auth_headers
      positions = response.parsed_body["positions"]
      expect(positions.length).to eq(1)
      expect(positions.first["market_value"]).to eq(5000.0)
    end

    it "returns by_asset_class grouped totals" do
      security = create(:security)
      create(:position_snapshot, security: security, asset_class: "Equity", market_value: 1000.0)

      get "/api/v1/portfolio", headers: auth_headers
      expect(response.parsed_body["by_asset_class"]).to include("Equity")
    end

    it "returns portfolio_history as a hash keyed by date" do
      security = create(:security)
      create(:position_snapshot, security: security, as_of_date: Date.current, market_value: 1000.0)

      get "/api/v1/portfolio", headers: auth_headers
      expect(response.parsed_body["portfolio_history"]).to be_a(Hash)
    end
  end
end
