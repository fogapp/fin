require "rails_helper"

RSpec.describe CoinbaseClient do
  before do
    # Persist a configuration with a valid Ed25519 seed so the constructor
    # can build the PKCS#8 PEM and load it via OpenSSL.
    seed   = SecureRandom.bytes(32)
    secret = Base64.strict_encode64(seed + SecureRandom.bytes(32))
    CoinbaseConfiguration.create!(api_key_id: "test-key-id", api_key_secret: secret)
  end

  describe ".new" do
    it "raises when no credentials are configured" do
      CoinbaseConfiguration.delete_all
      original_id     = ENV.delete("COINBASE_API_KEY_ID")
      original_secret = ENV.delete("COINBASE_API_KEY_SECRET")
      expect { described_class.new }.to raise_error(ArgumentError, /credentials not configured/)
    ensure
      ENV["COINBASE_API_KEY_ID"]     = original_id     if original_id
      ENV["COINBASE_API_KEY_SECRET"] = original_secret if original_secret
    end
  end

  describe "#accounts" do
    it "GETs /v2/accounts with an EdDSA bearer token and returns the data array" do
      account_payload = { "id" => "uuid-1", "name" => "BTC Wallet", "balance" => { "amount" => "0.5", "currency" => "BTC" } }
      stub_request(:get, "https://api.coinbase.com/v2/accounts?limit=250")
        .with { |req| req.headers["Authorization"].start_with?("Bearer ") &&
                      req.headers["Content-Type"] == "application/json" &&
                      req.headers["Cb-Version"] == "2024-01-01" }
        .to_return(status: 200, body: { "data" => [ account_payload ] }.to_json)

      expect(described_class.new.accounts).to eq([ account_payload ])
    end

    it "honors a custom limit parameter" do
      stub_request(:get, "https://api.coinbase.com/v2/accounts?limit=50")
        .to_return(status: 200, body: { "data" => [] }.to_json)

      expect(described_class.new.accounts(limit: 50)).to eq([])
    end

    it "raises with the Coinbase error message on non-success responses" do
      stub_request(:get, %r{api\.coinbase\.com/v2/accounts})
        .to_return(status: 401, body: { "error" => "unauthorized" }.to_json)

      expect { described_class.new.accounts }.to raise_error(/Coinbase 401: unauthorized/)
    end

    it "falls back to body text when the error response is not JSON" do
      stub_request(:get, %r{api\.coinbase\.com/v2/accounts})
        .to_return(status: 500, body: "down for maintenance")

      expect { described_class.new.accounts }.to raise_error(/Coinbase 500: down for maintenance/)
    end
  end

  describe "#account_transactions" do
    it "GETs /v2/accounts/:id/transactions with expand=all" do
      stub_request(:get, %r{api\.coinbase\.com/v2/accounts/uuid-1/transactions})
        .with(query: hash_including(limit: "100", expand: "all"))
        .to_return(status: 200, body: { "data" => [] }.to_json)

      expect(described_class.new.account_transactions("uuid-1")).to include("data" => [])
    end

    it "passes starting_after for pagination" do
      stub_request(:get, %r{api\.coinbase\.com/v2/accounts/uuid-1/transactions})
        .with(query: hash_including(starting_after: "cursor-x"))
        .to_return(status: 200, body: { "data" => [] }.to_json)

      described_class.new.account_transactions("uuid-1", starting_after: "cursor-x")
      expect(WebMock).to have_requested(:get, %r{starting_after=cursor-x}).once
    end
  end
end
