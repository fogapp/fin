require "rails_helper"

RSpec.describe "Api::V1::CoinMarketCap::Configurations", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/coin_market_cap/configuration" do
    it "returns the unconfigured state when no record exists" do
      get "/api/v1/coin_market_cap/configuration", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("api_key_set" => false, "configured" => false)
    end

    it "reports the configured state when an api_key is present" do
      CoinMarketCapConfiguration.create!(api_key: "k")
      get "/api/v1/coin_market_cap/configuration", headers: auth_headers
      expect(response.parsed_body).to eq("api_key_set" => true, "configured" => true)
    end
  end

  describe "PATCH /api/v1/coin_market_cap/configuration" do
    it "saves the api_key and returns the configured state" do
      patch "/api/v1/coin_market_cap/configuration",
            params: { coin_market_cap_configuration: { api_key: "k" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["configured"]).to be true
      expect(CoinMarketCapConfiguration.current.api_key).to eq("k")
    end
  end

  describe "POST /api/v1/coin_market_cap/configuration/test" do
    before { CoinMarketCapConfiguration.create!(api_key: "k") }

    it "returns ok with the BTC price when the probe succeeds" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 200, body: {
          "data" => { "BTC" => [ { "slug" => "bitcoin", "quote" => { "USD" => { "price" => 50_000.0 } } } ] }
        }.to_json)

      post "/api/v1/coin_market_cap/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true)
      expect(response.parsed_body["message"]).to include("$50000.0")
    end

    it "returns 422 when no BTC price comes back" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 200, body: { "data" => {} }.to_json)

      post "/api/v1/coin_market_cap/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["ok"]).to be false
    end

    it "returns 422 with the error message when the API errors" do
      stub_request(:get, %r{pro-api.coinmarketcap.com})
        .to_return(status: 401, body: { "status" => { "error_message" => "bad key" } }.to_json)

      post "/api/v1/coin_market_cap/configuration/test", headers: auth_headers
      expect(response.parsed_body["error"]).to include("bad key")
    end

    it "hides the message for unexpected (non-CMC) errors (A3)" do
      # NoMethodError stands in for anything that isn't a CoinMarketCap::Error
      # — its message could leak internal state and must not be surfaced.
      allow_any_instance_of(::CoinMarketCap::Client).to receive(:quotes).and_raise(
        NoMethodError, "undefined method 'foo' for #<Internal::Thing>"
      )

      post "/api/v1/coin_market_cap/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("CoinMarketCap connection failed")
      expect(response.parsed_body["error"]).not_to include("Internal")
    end
  end
end
