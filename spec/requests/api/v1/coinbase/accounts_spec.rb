require "rails_helper"

RSpec.describe "Api::V1::Coinbase::Accounts", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/coinbase/accounts" do
    it "returns 422 when no Coinbase credentials are configured" do
      get "/api/v1/coinbase/accounts", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/not configured/)
    end

    context "with credentials configured" do
      before do
        seed   = SecureRandom.bytes(32)
        secret = Base64.strict_encode64(seed + SecureRandom.bytes(32))
        CoinbaseConfiguration.create!(api_key_id: "k", api_key_secret: secret)
      end

      it "lists remote accounts and merges in local balance_usd when a matching Account exists" do
        broker = create(:broker, name: "Coinbase")
        create(:account, broker: broker, account_number: "remote-1", balance_usd: 12_500.0)

        stub_request(:get, %r{api\.coinbase\.com/v2/accounts}).to_return(
          status: 200, body: { "data" => [
            { "id" => "remote-1", "name" => "BTC Wallet", "type" => "wallet",
              "balance" => { "amount" => "0.25", "currency" => "BTC" } },
            { "id" => "remote-2", "name" => "USD Wallet", "type" => "fiat",
              "balance" => { "amount" => "100.00", "currency" => "USD" } }
          ] }.to_json
        )

        get "/api/v1/coinbase/accounts", headers: auth_headers
        expect(response).to have_http_status(:ok)

        body = response.parsed_body
        expect(body.length).to eq(2)
        remote_1 = body.find { |a| a["id"] == "remote-1" }
        expect(remote_1).to include("name" => "BTC Wallet", "currency" => "BTC",
                                    "balance" => "0.25", "type" => "wallet",
                                    "balance_usd" => 12_500.0)
        expect(body.find { |a| a["id"] == "remote-2" }["balance_usd"]).to be_nil
      end

      it "returns balance_usd=nil for all rows when the local Coinbase broker is absent" do
        stub_request(:get, %r{api\.coinbase\.com/v2/accounts}).to_return(
          status: 200, body: { "data" => [
            { "id" => "remote-1", "name" => "BTC Wallet", "type" => "wallet",
              "balance" => { "amount" => "0.25", "currency" => "BTC" } }
          ] }.to_json
        )

        get "/api/v1/coinbase/accounts", headers: auth_headers
        expect(response.parsed_body.first["balance_usd"]).to be_nil
      end
    end
  end
end
