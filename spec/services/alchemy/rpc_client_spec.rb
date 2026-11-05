require "rails_helper"

RSpec.describe Alchemy::RpcClient do
  let(:endpoint) { "https://eth-mainnet.g.alchemy.com/v2/test-alchemy-key" }
  let(:client)   { described_class.new(network: "eth-mainnet") }

  before { create(:alchemy_configuration) }

  def rpc_result(result)
    { status: 200, body: { "jsonrpc" => "2.0", "id" => 1, "result" => result }.to_json }
  end

  describe "#block_number" do
    it "returns the head block as an integer" do
      stub_request(:post, endpoint)
        .with(body: hash_including("method" => "eth_blockNumber"))
        .to_return(rpc_result("0x1499d64"))

      expect(client.block_number).to eq(21601636)
    end
  end

  describe "#asset_transfers" do
    it "requests one direction with hex block range and network categories" do
      stub = stub_request(:post, endpoint)
        .with { |req|
          params = JSON.parse(req.body)["params"].first
          params["fromAddress"] == "0xabc" &&
            !params.key?("toAddress") &&
            params["fromBlock"] == "0x64" &&
            params["toBlock"] == "0xc8" &&
            params["category"] == %w[external erc20 internal] &&
            params["order"] == "asc"
        }
        .to_return(rpc_result("transfers" => [ { "uniqueId" => "0xdead:external" } ]))

      page = client.asset_transfers(address: "0xabc", direction: :from, from_block: 100, to_block: 200)
      expect(stub).to have_been_requested
      expect(page.transfers.size).to eq(1)
      expect(page.page_key).to be_nil
    end

    it "omits the internal category on networks that do not support it" do
      stub = stub_request(:post, "https://base-mainnet.g.alchemy.com/v2/test-alchemy-key")
        .with { |req| JSON.parse(req.body)["params"].first["category"] == %w[external erc20] }
        .to_return(rpc_result("transfers" => []))

      described_class.new(network: "base-mainnet")
        .asset_transfers(address: "0xabc", direction: :to, from_block: 0, to_block: 10)
      expect(stub).to have_been_requested
    end

    it "returns the pageKey and passes it back on the next call" do
      stub_request(:post, endpoint)
        .with { |req| JSON.parse(req.body)["params"].first["pageKey"].nil? }
        .to_return(rpc_result("transfers" => [], "pageKey" => "abc123"))

      page = client.asset_transfers(address: "0xabc", direction: :to, from_block: 0, to_block: 10)
      expect(page.page_key).to eq("abc123")

      stub2 = stub_request(:post, endpoint)
        .with { |req| JSON.parse(req.body)["params"].first["pageKey"] == "abc123" }
        .to_return(rpc_result("transfers" => []))

      client.asset_transfers(address: "0xabc", direction: :to, from_block: 0, to_block: 10, page_key: "abc123")
      expect(stub2).to have_been_requested
    end

    it "raises Error on a JSON-RPC error body" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { "jsonrpc" => "2.0", "id" => 1, "error" => { "code" => -32600, "message" => "bad range" } }.to_json
      )

      expect {
        client.asset_transfers(address: "0xabc", direction: :from, from_block: 0, to_block: 10)
      }.to raise_error(Alchemy::RpcClient::Error, /bad range/)
    end

    it "raises Error on an HTTP failure" do
      stub_request(:post, endpoint).to_return(status: 429, body: "")

      expect { client.block_number }.to raise_error(Alchemy::RpcClient::Error, /429/)
    end

    it "surfaces Alchemy's message from non-2xx error bodies" do
      stub_request(:post, endpoint).to_return(
        status: 403,
        body: { "jsonrpc" => "2.0", "id" => 1,
                "error" => { "code" => -32600,
                             "message" => "ETH_MAINNET is not enabled for this app." } }.to_json
      )

      expect { client.block_number }
        .to raise_error(Alchemy::RpcClient::Error, /403.*ETH_MAINNET is not enabled/)
    end
  end
end
