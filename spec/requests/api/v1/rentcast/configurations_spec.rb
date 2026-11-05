require "rails_helper"

RSpec.describe "Api::V1::Rentcast::Configurations", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/rentcast/configuration" do
    it "returns 401 without authentication" do
      get "/api/v1/rentcast/configuration"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the unconfigured state when no record exists" do
      get "/api/v1/rentcast/configuration", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("api_key_set" => false, "configured" => false)
      expect(response.parsed_body["quota"]).to include("used" => 0, "limit" => 50, "remaining" => 50)
    end

    it "reports usage and the property count once configured" do
      create(:rentcast_configuration, api_key: "k", requests_used: 11,
                                      quota_period_start: Date.current.beginning_of_month)
      create(:real_estate_property)

      get "/api/v1/rentcast/configuration", headers: auth_headers

      expect(response.parsed_body).to include("configured" => true, "property_count" => 1)
      expect(response.parsed_body["quota"]).to include("used" => 11, "remaining" => 39)
    end
  end

  describe "PATCH /api/v1/rentcast/configuration" do
    it "saves the api_key" do
      patch "/api/v1/rentcast/configuration",
            params: { rentcast_configuration: { api_key: "k" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["configured"]).to be true
      expect(RentcastConfiguration.unscoped.find_by(household: token.household).api_key).to eq("k")
    end

    it "saves a raised request limit for a paid plan" do
      patch "/api/v1/rentcast/configuration",
            params: { rentcast_configuration: { api_key: "k", monthly_request_limit: 1000 } },
            headers: auth_headers, as: :json

      expect(response.parsed_body["quota"]["limit"]).to eq(1000)
    end
  end

  describe "DELETE /api/v1/rentcast/configuration" do
    it "removes the key but keeps properties and their history" do
      create(:rentcast_configuration, api_key: "k")
      property = create(:real_estate_property)
      property.record_valuation!(source: RealEstateValuation::Source::Rentcast, as_of: Date.current, amount: 900_000)

      delete "/api/v1/rentcast/configuration", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(RentcastConfiguration.unscoped.where(household: token.household)).to be_empty
      expect(property.reload.current_value).to eq(900_000)
    end
  end

  describe "POST /api/v1/rentcast/configuration/test" do
    it "reports success when RentCast accepts the key" do
      create(:rentcast_configuration, api_key: "k")
      stub_request(:get, "https://api.rentcast.io/v1/properties")
        .with(query: hash_including({}))
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      post "/api/v1/rentcast/configuration/test", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to be true
    end

    it "relays a rejected key as a 422" do
      create(:rentcast_configuration, api_key: "bad")
      stub_request(:get, "https://api.rentcast.io/v1/properties")
        .with(query: hash_including({}))
        .to_return(status: 401, body: "{}")

      post "/api/v1/rentcast/configuration/test", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/RentCast rejected the request/)
    end

    it "does not leak internals when something unexpected fails" do
      create(:rentcast_configuration, api_key: "k")
      allow(Rentcast::Client).to receive(:new).and_raise(SocketError, "getaddrinfo: internal-host")

      post "/api/v1/rentcast/configuration/test", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("RentCast connection failed")
    end
  end
end
