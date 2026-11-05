require "rails_helper"

RSpec.describe "Api::V1::CostBasis", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/cost_basis" do
    it "returns 401 without authentication" do
      get "/api/v1/cost_basis"
      expect(response).to have_http_status(:unauthorized)
    end

    it "delegates to Api::Render::CostBasis and returns its payload" do
      get "/api/v1/cost_basis", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("summary", "positions")
      expect(body["positions"]).to be_an(Array)
    end

    it "ships the household's label with each position" do
      security = create(:security, ticker: "VMFXX", name: "Vanguard Federal MMF")
      create(:position_snapshot, account: create(:account), security: security,
                                 as_of_date: Date.current, quantity: 10, price: 1, market_value: 10)
      create(:security_label, security: security, household: token.household, label: "Emergency fund")

      get "/api/v1/cost_basis", headers: auth_headers
      position = response.parsed_body["positions"].find { |p| p["security_id"] == security.id }
      expect(position).to include("label" => "Emergency fund", "ticker" => "VMFXX")
    end
  end
end
