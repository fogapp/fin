require "rails_helper"

RSpec.describe "Api::V1::Plaid::Accounts", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/plaid/accounts" do
    it "returns 401 without authentication" do
      get "/api/v1/plaid/accounts"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns all plaid accounts with link status" do
      create(:plaid_account)

      get "/api/v1/plaid/accounts", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.first).to include("linked", "institution_name")
    end
  end

  describe "PATCH /api/v1/plaid/accounts/:id" do
    it "links the account and resets the item cursor" do
      item          = create(:plaid_item)
      plaid_account = create(:plaid_account, plaid_item: item)
      account       = create(:account)

      patch "/api/v1/plaid/accounts/#{plaid_account.id}",
            params: { account_id: account.id },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["linked"]).to be true
      expect(response.parsed_body["account_id"]).to eq(account.id)
      expect(item.reload.cursor).to be_nil
    end

    it "unlinks the account when account_id is blank" do
      account       = create(:account)
      plaid_account = create(:plaid_account, account: account)

      patch "/api/v1/plaid/accounts/#{plaid_account.id}",
            params: { account_id: nil },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["linked"]).to be false
    end

    it "returns 404 for a nonexistent plaid account" do
      patch "/api/v1/plaid/accounts/0", params: { account_id: nil }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/plaid/accounts/:id/sync" do
    it "queues a per-account sync job" do
      plaid_account = create(:plaid_account)
      allow(PlaidSyncJob).to receive(:perform_later)

      post "/api/v1/plaid/accounts/#{plaid_account.id}/sync", headers: auth_headers
      expect(response).to have_http_status(:accepted)
      expect(PlaidSyncJob).to have_received(:perform_later)
        .with(plaid_account.plaid_item_id, plaid_account.id)
    end
  end
end
