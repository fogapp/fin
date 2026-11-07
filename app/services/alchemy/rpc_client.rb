# typed: strict

module Alchemy
  # JSON-RPC client for one network's node endpoint — the transaction-sync
  # counterpart to AlchemyClient (which speaks the Portfolio REST API and
  # stays balance-only). asset_transfers returns a single page so callers
  # own pagination; backfill persists the pageKey between runs.
  class RpcClient
    extend T::Sig

    class Error < StandardError; end

    MAX_COUNT_HEX = T.let("0x3e8".freeze, String) # 1000, the API maximum

    TransferPage = Struct.new(:transfers, :page_key, keyword_init: true)

    sig { params(network: String, api_key: T.nilable(String)).void }
    def initialize(network:, api_key: nil)
      key = api_key.presence || AlchemyConfiguration.current.api_key.presence || ENV["ALCHEMY_API_KEY"]
      raise ArgumentError, "Alchemy API key not configured" if key.blank?

      @network = network
      @api_key = T.let(key, String)
    end

    sig { returns(Integer) }
    def block_number
      rpc("eth_blockNumber", []).to_i(16)
    end

    # One page of asset transfers touching `address` in one direction.
    # direction :from → transfers sent by the address, :to → received.
    sig do
      params(address: String, direction: Symbol, from_block: Integer,
             to_block: Integer, page_key: T.nilable(String)).returns(TransferPage)
    end
    def asset_transfers(address:, direction:, from_block:, to_block:, page_key: nil)
      params = {
        fromBlock:    "0x%x" % from_block,
        toBlock:      "0x%x" % to_block,
        category:     Networks.categories_for(@network),
        withMetadata: true,
        order:        "asc",
        maxCount:     MAX_COUNT_HEX
      }
      params[direction == :from ? :fromAddress : :toAddress] = address
      params[:pageKey] = page_key if page_key

      result = rpc("alchemy_getAssetTransfers", [ params ])
      TransferPage.new(
        transfers: Array(result["transfers"]),
        page_key:  result["pageKey"].presence
      )
    end

    private

    sig { params(method: String, params: T::Array[T.untyped]).returns(T.untyped) }
    def rpc(method, params)
      response = HttpJson.perform(
        :post, URI("https://#{@network}.g.alchemy.com/v2/#{@api_key}"),
        error: Error, label: "Alchemy RPC (#{method}, #{@network})", read_timeout: 30,
        headers: { "Content-Type" => "application/json" },
        body: { jsonrpc: "2.0", id: 1, method: method, params: params }
      )

      # Alchemy returns JSON-RPC error bodies even on non-2xx (e.g. 403
      # "ETH_MAINNET is not enabled for this app" with an enablement URL) —
      # surface the message either way, it's what makes the error fixable.
      body    = response.json_object
      message = ErrorMessage.from(response)

      unless response.success?
        raise Error, "Alchemy RPC #{response.code} (#{method}, #{@network})#{": #{message}" if message}"
      end
      raise Error, "Alchemy RPC error (#{method}, #{@network}): #{message || body['error']}" if body["error"]

      body.fetch("result")
    end
  end
end
