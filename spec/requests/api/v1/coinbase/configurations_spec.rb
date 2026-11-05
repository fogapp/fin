require "rails_helper"

RSpec.describe "Api::V1::Coinbase::Configurations", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/coinbase/configuration" do
    it "returns the unconfigured state when no record exists" do
      get "/api/v1/coinbase/configuration", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to eq("api_key_id_set" => false, "api_key_secret_set" => false, "configured" => false)
    end

    it "reports the configured state when both fields are present" do
      CoinbaseConfiguration.create!(api_key_id: "k", api_key_secret: "s")
      get "/api/v1/coinbase/configuration", headers: auth_headers
      body = response.parsed_body
      expect(body["api_key_id_set"]).to     be true
      expect(body["api_key_secret_set"]).to be true
      expect(body["configured"]).to         be true
    end
  end

  describe "PATCH /api/v1/coinbase/configuration" do
    it "creates the configuration and queues an initial sync" do
      expect {
        patch "/api/v1/coinbase/configuration",
              params: { coinbase_configuration: { api_key_id: "k", api_key_secret: "s" } },
              headers: auth_headers, as: :json
      }.to have_enqueued_job(CoinbaseSyncJob).with(Current.household.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["configured"]).to be true
    end

    it "does not queue a sync when re-saving an already-configured account" do
      CoinbaseConfiguration.create!(api_key_id: "old-k", api_key_secret: "old-s")

      expect {
        patch "/api/v1/coinbase/configuration",
              params: { coinbase_configuration: { api_key_id: "new-k" } },
              headers: auth_headers, as: :json
      }.not_to have_enqueued_job(CoinbaseSyncJob)
    end
  end

  describe "POST /api/v1/coinbase/configuration/test" do
    before do
      seed   = SecureRandom.bytes(32)
      secret = Base64.strict_encode64(seed + SecureRandom.bytes(32))
      CoinbaseConfiguration.create!(api_key_id: "k", api_key_secret: secret)
    end

    it "returns ok + a friendly message on a successful probe" do
      stub_request(:get, %r{api\.coinbase\.com/v2/accounts})
        .to_return(status: 200, body: { "data" => [ { "id" => "a" }, { "id" => "b" } ] }.to_json)

      post "/api/v1/coinbase/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true, "message" => match(/2 account/))
    end

    it "returns 422 with the error message when the probe fails" do
      stub_request(:get, %r{api\.coinbase\.com/v2/accounts})
        .to_return(status: 401, body: { "error" => "bad key" }.to_json)

      post "/api/v1/coinbase/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["ok"]).to be false
      expect(response.parsed_body["error"]).to include("bad key")
    end

    it "hides the message for unexpected (non-Coinbase) errors (A3)" do
      # NoMethodError stands in for anything that isn't a CoinbaseClient::Error
      # — its message could leak internal state and must not be surfaced.
      allow_any_instance_of(CoinbaseClient).to receive(:accounts).and_raise(
        NoMethodError, "undefined method 'foo' for #<Internal::Thing>"
      )

      post "/api/v1/coinbase/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Coinbase connection failed")
      expect(response.parsed_body["error"]).not_to include("Internal")
    end
  end
end
