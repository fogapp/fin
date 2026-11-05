require "rails_helper"

RSpec.describe "Api::V1::Alchemy::Wallets", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:address)      { "0xabc0000000000000000000000000000000006354" }

  describe "GET /api/v1/alchemy/wallets" do
    it "lists tracked wallets with account info" do
      wallet = create(:alchemy_wallet, name: "Main Vault")
      wallet.ensure_account!

      get "/api/v1/alchemy/wallets", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.size).to eq(1)
      expect(body.first["display_name"]).to eq("Main Vault")
      expect(body.first["networks"]).to eq([ "eth-mainnet", "base-mainnet" ])
      expect(body.first["account"]["name"]).to eq("Main Vault")
    end
  end

  describe "POST /api/v1/alchemy/wallets" do
    it "creates a wallet and queues a sync when configured" do
      create(:alchemy_configuration)

      expect {
        post "/api/v1/alchemy/wallets",
             params: { alchemy_wallet: { address: address, name: "Hot Wallet", networks: [ "eth-mainnet" ] } },
             headers: auth_headers, as: :json
      }.to have_enqueued_job(AlchemySyncJob).with(Current.household.id)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["address"]).to eq(address)
      expect(AlchemyWallet.count).to eq(1)
    end

    it "does not queue a sync without credentials" do
      expect {
        post "/api/v1/alchemy/wallets",
             params: { alchemy_wallet: { address: address } },
             headers: auth_headers, as: :json
      }.not_to have_enqueued_job(AlchemySyncJob)
      expect(response).to have_http_status(:created)
    end

    it "rejects an invalid address" do
      post "/api/v1/alchemy/wallets",
           params: { alchemy_wallet: { address: "not-an-address" } },
           headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/alchemy/wallets/:id" do
    it "updates name, networks and active flag" do
      wallet = create(:alchemy_wallet)

      patch "/api/v1/alchemy/wallets/#{wallet.id}",
            params: { alchemy_wallet: { name: "Cold Storage", networks: [ "base-mainnet" ], active: false } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      wallet.reload
      expect(wallet.name).to eq("Cold Storage")
      expect(wallet.networks).to eq([ "base-mainnet" ])
      expect(wallet.active).to be false
    end
  end

  describe "DELETE /api/v1/alchemy/wallets/:id" do
    it "removes the tracker but keeps the account" do
      wallet  = create(:alchemy_wallet)
      account = wallet.ensure_account!

      expect {
        delete "/api/v1/alchemy/wallets/#{wallet.id}", headers: auth_headers
      }.to change(AlchemyWallet, :count).by(-1)

      expect(response).to have_http_status(:no_content)
      expect(Account.exists?(account.id)).to be true
    end
  end

  describe "POST /api/v1/alchemy/wallets/:id/backfill" do
    it "resets sync state and enqueues a backfill per network" do
      AlchemyConfiguration.current.update!(api_key: "k", transactions_enabled: true)
      wallet = create(:alchemy_wallet, networks: %w[eth-mainnet base-mainnet])
      state  = AlchemyWalletSync.create!(alchemy_wallet: wallet, network: "eth-mainnet",
                                         household_id: wallet.household_id,
                                         backfill_status: "completed", backfill_transfer_count: 42)

      expect {
        post "/api/v1/alchemy/wallets/#{wallet.id}/backfill", headers: auth_headers
      }.to have_enqueued_job(Alchemy::BackfillJob).with(wallet.id, "eth-mainnet")
        .and have_enqueued_job(Alchemy::BackfillJob).with(wallet.id, "base-mainnet")

      expect(response).to have_http_status(:accepted)
      state.reload
      expect(state.backfill_status).to eq(AlchemyWalletSync::BackfillStatus::Pending)
      expect(state.backfill_transfer_count).to eq(0)
    end

    it "422s when transaction sync is not enabled" do
      wallet = create(:alchemy_wallet)

      post "/api/v1/alchemy/wallets/#{wallet.id}/backfill", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
