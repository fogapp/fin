require "rails_helper"

RSpec.describe "Api::V1::NetWorth", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/net_worth/projection" do
    it "returns 401 without authentication" do
      get "/api/v1/net_worth/projection"
      expect(response).to have_http_status(:unauthorized)
    end

    it "compounds the latest net worth with growth and monthly contributions" do
      create(:metric_point, metric_key: "net_worth", date: Date.current - 1, value: 100_000)

      get "/api/v1/net_worth/projection",
          params: { years: 1, growth: 12, monthly: 1000 }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["starting"]).to eq(100_000.0)
      expect(body["monthly_contribution"]).to eq(1000.0)
      expect(body["annual_growth_percent"]).to eq(12.0)
      expect(body["series"].length).to eq(12)
      # First month: 100k * 1.01 + 1000
      expect(body["series"].first["value"]).to eq(102_000.0)
      expect(body["series"].last["value"]).to be > body["series"].first["value"]
    end

    it "defaults the contribution to trailing average net savings" do
      account = create(:account)
      last_month = Date.current.prev_month.beginning_of_month
      create(:cash_transaction, :bank, :credit, account: account, amount: 6000, transaction_date: last_month + 2)
      create(:cash_transaction, :credit_card, :sale, account: account, amount: -2400, transaction_date: last_month + 3)

      get "/api/v1/net_worth/projection", headers: auth_headers

      # (6000 - 2400) / 12 closed months
      expect(response.parsed_body["monthly_contribution"]).to eq(300.0)
      expect(response.parsed_body["years"]).to eq(10)
    end

    it "clamps years into 1..40" do
      get "/api/v1/net_worth/projection", params: { years: 99 }, headers: auth_headers
      expect(response.parsed_body["years"]).to eq(40)
    end
  end

  describe "GET /api/v1/net_worth" do
    it "returns 401 without authentication" do
      get "/api/v1/net_worth"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the full net worth payload" do
      account = create(:account, account_type: "Checking", balance: 1000, balance_usd: 1000)
      AccountBalanceSnapshot.create!(account: account, balance: 900, balance_currency: "USD",
                                     balance_usd: 900, source: "scheduled", recorded_at: 5.days.ago)

      get "/api/v1/net_worth", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("range", "series", "stats", "monthly_deltas", "accounts", "loans")
      expect(body["range"]).to eq("1y")
      expect(body["stats"]["net_worth"]).to eq(1000.0)
      expect(body["series"].last).to include(
        "date" => Date.current.iso8601, "cash" => 1000.0, "net" => 1000.0
      )
      expect(body["accounts"].first).to include("name" => account.name, "group" => "cash")
    end

    it "accepts a range parameter" do
      get "/api/v1/net_worth", params: { range: "3m" }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["range"]).to eq("3m")
    end

    it "accepts an explicit from/to window" do
      from = 40.days.ago.to_date
      to   = 10.days.ago.to_date
      get "/api/v1/net_worth", params: { from: from.iso8601, to: to.iso8601 }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("from" => from.iso8601, "to" => to.iso8601)
      expect(body["series"].first["date"]).to eq(from.iso8601)
      expect(body["series"].last["date"]).to eq(to.iso8601)
    end

    it "rejects a malformed date with 400" do
      get "/api/v1/net_worth", params: { from: "2025-13-45" }, headers: auth_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects unknown range values with 422, defaulting only when blank" do
      get "/api/v1/net_worth", params: { range: "bogus" }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("range must be one of")

      get "/api/v1/net_worth", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["range"]).to eq("1y")
    end

    it "does not leak other households' data" do
      other = create(:household)
      Current.set(household: other, user: Current.user) do
        create(:account, account_type: "Checking", balance: 5000, balance_usd: 5000,
                         broker: create(:broker))
      end

      get "/api/v1/net_worth", headers: auth_headers
      expect(response.parsed_body["stats"]["net_worth"]).to eq(0.0)
    end
  end
end
