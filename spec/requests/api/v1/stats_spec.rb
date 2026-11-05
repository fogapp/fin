require "rails_helper"

RSpec.describe "Api::V1::Stats", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/stats" do
    it "returns 401 without authentication" do
      get "/api/v1/stats"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns every registered metric with metadata, ordered groups, and as_of" do
      get "/api/v1/stats", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["groups"].map { |g| g["key"] }).to eq(%w[cashflow investments net_worth])
      expect(body["stats"].map { |s| s["key"] })
        .to match_array(Metrics::Registry.all.map { |d| d.key.to_s })
      expect(body["stats"].first).to include("label", "unit", "granularity", "value_type", "direction", "group")
    end

    it "serves latest value, partial flag, change, and sparkline from stored points" do
      this_month = Date.current.beginning_of_month
      create(:metric_point, metric_key: "monthly_spend", date: this_month << 2, value: 900)
      create(:metric_point, metric_key: "monthly_spend", date: this_month << 1, value: 1000)
      create(:metric_point, metric_key: "monthly_spend", date: this_month, value: 500)

      get "/api/v1/stats", headers: auth_headers

      stat = response.parsed_body["stats"].find { |s| s["key"] == "monthly_spend" }
      expect(stat["latest"]).to include("date" => this_month.strftime("%Y-%m"), "value" => 500.0, "partial" => true)
      expect(stat["previous"]).to include("value" => 1000.0, "partial" => false)
      expect(stat["sparkline"].size).to eq(3)
      expect(stat["pace"]).to include("projected")
      expect(stat["drill"]).to be_present
    end

    it "does not leak another household's points" do
      other = Household.create!(name: "Other")
      Current.set(household: other) do
        create(:metric_point, metric_key: "monthly_spend",
               date: Date.current.beginning_of_month, value: 777)
      end

      get "/api/v1/stats", headers: auth_headers

      stat = response.parsed_body["stats"].find { |s| s["key"] == "monthly_spend" }
      expect(stat["latest"]).to be_nil
    end
  end

  describe "GET /api/v1/stats/:key" do
    it "returns 404 for an unknown key" do
      get "/api/v1/stats/not_a_metric", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 400 for a malformed date param" do
      get "/api/v1/stats/monthly_spend", params: { from: "nope" }, headers: auth_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns series, summary, and metadata with month-encoded dates" do
      this_month = Date.current.beginning_of_month
      create(:metric_point, metric_key: "monthly_spend", date: this_month << 2, value: 800)
      create(:metric_point, metric_key: "monthly_spend", date: this_month << 1, value: 1200)
      create(:metric_point, metric_key: "monthly_spend", date: this_month, value: 300)

      get "/api/v1/stats/monthly_spend", headers: auth_headers

      body = response.parsed_body
      expect(body).to include("key" => "monthly_spend", "unit" => "currency", "value_type" => "flow", "direction" => "down_good")
      expect(body["series"].map { |p| p["date"] })
        .to eq([ (this_month << 2).strftime("%Y-%m"), (this_month << 1).strftime("%Y-%m"), this_month.strftime("%Y-%m") ])
      expect(body["series"].last["partial"]).to be(true)

      summary = body["summary"]
      # Partial current month excluded from min/max/avg
      expect(summary["min"]).to include("value" => 800.0)
      expect(summary["max"]).to include("value" => 1200.0)
      expect(summary["avg"]).to eq(1000.0)
      expect(summary["latest"]).to include("value" => 300.0, "partial" => true)
      expect(summary["previous"]).to include("value" => 1200.0)
      expect(summary["changes"]).to include("1m", "3m", "ytd", "1y")
    end

    it "respects from/to range params" do
      this_month = Date.current.beginning_of_month
      create(:metric_point, metric_key: "monthly_spend", date: this_month << 5, value: 100)
      create(:metric_point, metric_key: "monthly_spend", date: this_month << 1, value: 200)

      get "/api/v1/stats/monthly_spend",
          params: { from: (this_month << 2).iso8601, to: Date.current.iso8601 },
          headers: auth_headers

      expect(response.parsed_body["series"].size).to eq(1)
      expect(response.parsed_body["series"].first["value"]).to eq(200.0)
    end

    it "computes live breakdowns for metrics that define them" do
      merchant = create(:merchant, name: "Amazon")
      create(:cash_transaction, :credit_card, :sale, merchant: merchant, transaction_date: Date.current)
      create(:metric_point, metric_key: "cc_transaction_count", date: Date.current.beginning_of_month, value: 1)

      get "/api/v1/stats/cc_transaction_count", headers: auth_headers

      breakdown = response.parsed_body["breakdowns"].first
      expect(breakdown["label"]).to eq("Top merchants")
      expect(breakdown["rows"].first).to include("label" => "Amazon", "value" => 1)
    end
  end
end
