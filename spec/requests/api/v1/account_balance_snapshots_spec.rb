require "rails_helper"

RSpec.describe "Api::V1::AccountBalanceSnapshots", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account)      { create(:account) }

  describe "GET /api/v1/accounts/:account_id/balance_snapshots" do
    it "returns 401 without authentication" do
      get "/api/v1/accounts/#{account.id}/balance_snapshots"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the daily series for an account" do
      AccountBalanceSnapshot.create!(account: account, balance: 100.00, balance_currency: "USD",
                                     balance_usd: 100.00, source: "scheduled",
                                     recorded_at: 2.days.ago)
      AccountBalanceSnapshot.create!(account: account, balance: 150.00, balance_currency: "USD",
                                     balance_usd: 150.00, source: "scheduled",
                                     recorded_at: 1.day.ago)

      get "/api/v1/accounts/#{account.id}/balance_snapshots", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.length).to eq(2)
      expect(body.first).to include("date", "balance", "balance_currency", "balance_usd", "source")
      expect(body.first["balance"]).to eq(100.0)
    end

    it "returns 404 for a nonexistent account" do
      get "/api/v1/accounts/00000000-0000-0000-0000-000000000000/balance_snapshots",
          headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
