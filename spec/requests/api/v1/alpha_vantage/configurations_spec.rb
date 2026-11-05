require "rails_helper"

RSpec.describe "Api::V1::AlphaVantage::Configurations", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/alpha_vantage/configuration" do
    it "returns 401 without authentication" do
      get "/api/v1/alpha_vantage/configuration"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the unconfigured state when no record exists" do
      get "/api/v1/alpha_vantage/configuration", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("api_key_set" => false, "configured" => false)
    end

    it "reports the configured state when an api_key is present" do
      AlphaVantageConfiguration.create!(api_key: "k", household: token.household)
      get "/api/v1/alpha_vantage/configuration", headers: auth_headers
      expect(response.parsed_body).to eq("api_key_set" => true, "configured" => true)
    end
  end

  describe "PATCH /api/v1/alpha_vantage/configuration" do
    it "saves the api_key and returns the configured state" do
      patch "/api/v1/alpha_vantage/configuration",
            params: { alpha_vantage_configuration: { api_key: "k" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["configured"]).to be true
      expect(AlphaVantageConfiguration.unscoped.find_by(household: token.household).api_key).to eq("k")
    end
  end

  describe "POST /api/v1/alpha_vantage/configuration/test" do
    before { AlphaVantageConfiguration.create!(api_key: "k", household: token.household) }

    it "returns ok when the symbol-search probe succeeds" do
      stub_request(:get, %r{www.alphavantage.co/query})
        .to_return(status: 200, body: {
          "bestMatches" => [ { "1. symbol" => "AAPL", "2. name" => "Apple Inc", "9. matchScore" => "1.0" } ]
        }.to_json)

      post "/api/v1/alpha_vantage/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true)
      expect(response.parsed_body["message"]).to include("1 matches")
    end

    it "returns 422 when the probe returns nothing" do
      stub_request(:get, %r{www.alphavantage.co/query})
        .to_return(status: 200, body: { "bestMatches" => [] }.to_json)

      post "/api/v1/alpha_vantage/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("ok" => false)
    end
  end
end
