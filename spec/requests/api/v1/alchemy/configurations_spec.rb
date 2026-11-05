require "rails_helper"

RSpec.describe "Api::V1::Alchemy::Configurations", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/alchemy/configuration" do
    it "returns the unconfigured state when no record exists" do
      get "/api/v1/alchemy/configuration", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "api_key_set" => false, "configured" => false,
        "transactions_enabled" => false, "sync_frequency" => "daily",
        "auth_token_set" => false, "webhooks" => []
      )
      expect(response.parsed_body["suggested_webhook_base_url"]).to be_present
    end
  end

  describe "PATCH /api/v1/alchemy/configuration" do
    it "creates the configuration and queues a sync when wallets exist" do
      create(:alchemy_wallet)

      expect {
        patch "/api/v1/alchemy/configuration",
              params: { alchemy_configuration: { api_key: "k" } },
              headers: auth_headers, as: :json
      }.to have_enqueued_job(AlchemySyncJob).with(Current.household.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["configured"]).to be true
    end

    it "does not queue a sync when no wallets are tracked yet" do
      expect {
        patch "/api/v1/alchemy/configuration",
              params: { alchemy_configuration: { api_key: "k" } },
              headers: auth_headers, as: :json
      }.not_to have_enqueued_job(AlchemySyncJob)
    end

    it "enables transaction sync, kicking off the first sync and a webhook reconcile" do
      create(:alchemy_configuration)

      expect {
        patch "/api/v1/alchemy/configuration",
              params: { alchemy_configuration: { transactions_enabled: true, sync_frequency: "hourly" } },
              headers: auth_headers, as: :json
      }.to have_enqueued_job(Alchemy::TransactionSyncJob).with(Current.household.id)
        .and have_enqueued_job(Alchemy::WebhookSyncJob)

      body = response.parsed_body
      expect(body["transactions_enabled"]).to be true
      expect(body["sync_frequency"]).to eq("hourly")
    end

    it "422s an unknown sync_frequency listing the allowed values" do
      create(:alchemy_configuration)

      patch "/api/v1/alchemy/configuration",
            params: { alchemy_configuration: { sync_frequency: "yearly" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("realtime", "daily")
    end

    it "stores the Notify auth token and webhook base URL without echoing the token" do
      create(:alchemy_configuration)

      patch "/api/v1/alchemy/configuration",
            params: { alchemy_configuration: { auth_token: "tok", webhook_base_url: "https://fin.example.com" } },
            headers: auth_headers, as: :json

      body = response.parsed_body
      expect(body["auth_token_set"]).to be true
      expect(body["webhook_base_url"]).to eq("https://fin.example.com")
      expect(body).not_to have_key("auth_token")
    end
  end

  describe "POST /api/v1/alchemy/configuration/test" do
    before { create(:alchemy_configuration) }

    it "returns ok on a successful probe" do
      stub_request(:post, %r{api\.g\.alchemy\.com/data/v1})
        .to_return(status: 200, body: { "data" => { "tokens" => [] } }.to_json)

      post "/api/v1/alchemy/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to be true
    end

    it "returns 422 with the error message when the probe fails" do
      stub_request(:post, %r{api\.g\.alchemy\.com/data/v1})
        .to_return(status: 401, body: { "error" => { "message" => "invalid api key" } }.to_json)

      post "/api/v1/alchemy/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("invalid api key")
    end

    it "hides the message for unexpected errors" do
      allow_any_instance_of(AlchemyClient).to receive(:test_connection!).and_raise(
        NoMethodError, "undefined method 'foo' for #<Internal::Thing>"
      )

      post "/api/v1/alchemy/configuration/test", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Alchemy connection failed")
    end
  end
end
