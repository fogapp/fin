require "rails_helper"

RSpec.describe "Api::V1::Plaid::Items", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/plaid/items" do
    it "returns 401 without authentication" do
      get "/api/v1/plaid/items"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns connected institutions with their accounts" do
      item = create(:plaid_item, institution_name: "Chase")
      create(:plaid_account, plaid_item: item)

      get "/api/v1/plaid/items", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.first["institution_name"]).to eq("Chase")
      expect(body.first["plaid_accounts"].length).to eq(1)
    end

    it "counts transactions per linked account by source" do
      account = create(:account)
      item = create(:plaid_item)
      create(:plaid_account, plaid_item: item, account: account)
      create_list(:cash_transaction, 2, :bank, account: account)
      create(:cash_transaction, :credit_card, :sale, account: account)
      create(:cash_transaction, :bank, account: create(:account)) # not linked

      get "/api/v1/plaid/items", headers: auth_headers

      row = response.parsed_body.first["plaid_accounts"].sole
      expect(row).to include("bank_count" => 2, "credit_card_count" => 1)
    end
  end

  describe "POST /api/v1/plaid/items" do
    let(:plaid_client) { instance_double(PlaidClient) }

    before do
      allow(PlaidClient).to receive(:new).and_return(plaid_client)
      allow(plaid_client).to receive(:exchange_public_token).and_return(
        double(item_id: "item-abc", access_token: "access-abc")
      )
      allow(plaid_client).to receive(:get_item).and_return(
        double(item: double(institution_id: "ins_1"))
      )
      allow(plaid_client).to receive(:get_institution).and_return(
        double(institution: double(name: "Test Bank"))
      )
      allow(plaid_client).to receive(:get_accounts).and_return(
        double(accounts: [
          double(account_id: "acct-1", name: "Checking", mask: "1234", type: "depository", subtype: "checking")
        ])
      )
    end

    it "exchanges a public token and returns the created item" do
      post "/api/v1/plaid/items",
           params: { public_token: "public-token-abc" },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["institution_name"]).to eq("Test Bank")
      expect(response.parsed_body["plaid_accounts"].length).to eq(1)
      expect(PlaidItem.count).to eq(1)
    end
  end

  describe "DELETE /api/v1/plaid/items/:id" do
    it "disconnects the institution and returns 204" do
      item = create(:plaid_item)
      delete "/api/v1/plaid/items/#{item.id}", headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(PlaidItem.exists?(item.id)).to be false
    end

    it "returns 404 for a nonexistent item" do
      delete "/api/v1/plaid/items/0", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/plaid/items/:id/sync" do
    it "queues a sync job and returns status" do
      item = create(:plaid_item)
      allow(PlaidSyncJob).to receive(:perform_later)

      post "/api/v1/plaid/items/#{item.id}/sync", headers: auth_headers
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["status"]).to eq("queued")
      expect(PlaidSyncJob).to have_received(:perform_later).with(item.id)
    end
  end
end
