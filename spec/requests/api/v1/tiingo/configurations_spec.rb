require "rails_helper"

RSpec.describe "Api::V1::Tiingo::Configurations", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/tiingo/configuration" do
    it "returns 401 without authentication" do
      get "/api/v1/tiingo/configuration"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the unconfigured state when no record exists" do
      get "/api/v1/tiingo/configuration", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("api_key_set" => false, "configured" => false)
    end

    it "reports the configured state when an api_key is present" do
      TiingoConfiguration.create!(api_key: "k", household: token.household)
      get "/api/v1/tiingo/configuration", headers: auth_headers
      expect(response.parsed_body).to eq("api_key_set" => true, "configured" => true)
    end
  end

  describe "PATCH /api/v1/tiingo/configuration" do
    it "saves the api_key, re-pins provider defaults, and returns the configured state" do
      expect(MarketData::Router).to receive(:repin_defaults!)

      patch "/api/v1/tiingo/configuration",
            params: { tiingo_configuration: { api_key: "k" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["configured"]).to be true
      expect(TiingoConfiguration.unscoped.find_by(household: token.household).api_key).to eq("k")
    end
  end

  describe "DELETE /api/v1/tiingo/configuration" do
    it "removes the configuration and re-pins provider defaults" do
      TiingoConfiguration.create!(api_key: "k", household: token.household)
      expect(MarketData::Router).to receive(:repin_defaults!)

      delete "/api/v1/tiingo/configuration", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(TiingoConfiguration.unscoped.where(household: token.household)).to be_empty
    end
  end

  describe "POST /api/v1/tiingo/configuration/test" do
    before { TiingoConfiguration.create!(api_key: "k", household: token.household) }

    it "returns ok when the probe succeeds" do
      stub_request(:get, "https://api.tiingo.com/api/test")
        .to_return(status: 200, body: { "message" => "You successfully sent a request" }.to_json)

      post "/api/v1/tiingo/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true)
    end

    it "returns 422 when the key is rejected" do
      stub_request(:get, "https://api.tiingo.com/api/test")
        .to_return(status: 401, body: "")

      post "/api/v1/tiingo/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("ok" => false)
    end
  end
end
