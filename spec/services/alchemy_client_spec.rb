require "rails_helper"

RSpec.describe AlchemyClient do
  let(:endpoint) { "https://api.g.alchemy.com/data/v1/test-alchemy-key/assets/tokens/by-address" }

  before { create(:alchemy_configuration) }

  def token_entry(network: "eth-mainnet", token_address: nil, balance: "0x0de0b6b3a7640000",
                  symbol: "ETH", name: "Ethereum", decimals: 18, price: "1800.0")
    {
      "network"       => network,
      "tokenAddress"  => token_address,
      "tokenBalance"  => balance,
      "tokenMetadata" => { "symbol" => symbol, "name" => name, "decimals" => decimals, "logo" => nil },
      "tokenPrices"   => price ? [ { "currency" => "usd", "value" => price, "lastUpdatedAt" => "2026-07-12T00:00:00Z" } ] : [],
      "error"         => nil
    }
  end

  describe "#tokens_by_address" do
    it "posts the address with networks and returns token entries" do
      stub = stub_request(:post, endpoint)
        .with(body: hash_including(
          "addresses" => [ { "address" => "0xabc", "networks" => [ "eth-mainnet", "base-mainnet" ] } ],
          "withPrices" => true
        ))
        .to_return(status: 200, body: { "data" => { "tokens" => [ token_entry ] } }.to_json)

      tokens = described_class.new.tokens_by_address("0xabc", networks: %w[eth-mainnet base-mainnet])
      expect(stub).to have_been_requested
      expect(tokens.size).to eq(1)
      expect(tokens.first["tokenMetadata"]["symbol"]).to eq("ETH")
    end

    it "follows pageKey pagination" do
      page1 = { "data" => { "tokens" => [ token_entry ], "pageKey" => "next-page" } }
      page2 = { "data" => { "tokens" => [ token_entry(symbol: "USDC") ] } }
      stub_request(:post, endpoint).to_return(
        { status: 200, body: page1.to_json },
        { status: 200, body: page2.to_json }
      )

      tokens = described_class.new.tokens_by_address("0xabc", networks: [ "eth-mainnet" ])
      expect(tokens.size).to eq(2)
    end

    it "raises AlchemyClient::Error with the API message on failure" do
      stub_request(:post, endpoint)
        .to_return(status: 401, body: { "error" => { "message" => "invalid api key" } }.to_json)

      expect {
        described_class.new.tokens_by_address("0xabc", networks: [ "eth-mainnet" ])
      }.to raise_error(AlchemyClient::Error, /401.*invalid api key/)
    end
  end

  describe ".to_quantity" do
    it "converts hex balances using token decimals" do
      # 1 ETH = 10^18 wei = 0x0de0b6b3a7640000
      expect(described_class.to_quantity("0x0de0b6b3a7640000", 18)).to eq(BigDecimal(1))
    end

    it "handles decimal string balances" do
      expect(described_class.to_quantity("2500000", 6)).to eq(BigDecimal("2.5"))
    end

    it "returns zero for blank balances" do
      expect(described_class.to_quantity(nil, 18)).to eq(0)
      expect(described_class.to_quantity("", 18)).to eq(0)
    end
  end

  it "raises ArgumentError when no API key is configured" do
    AlchemyConfiguration.current.update!(api_key: nil)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALCHEMY_API_KEY").and_return(nil)
    expect { described_class.new }.to raise_error(ArgumentError, /not configured/)
  end
end
