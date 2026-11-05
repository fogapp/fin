require "rails_helper"

RSpec.describe "Api::V1::Coinbase::Sync", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "POST /api/v1/coinbase/sync" do
    it "returns 422 when no Coinbase credentials are configured" do
      post "/api/v1/coinbase/sync", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/not configured/)
    end

    it "queues a CoinbaseSyncJob and returns 202" do
      CoinbaseConfiguration.create!(api_key_id: "k", api_key_secret: "s")

      expect {
        post "/api/v1/coinbase/sync", headers: auth_headers
      }.to have_enqueued_job(CoinbaseSyncJob).with(Current.household.id)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["status"]).to eq("queued")
    end
  end
end
