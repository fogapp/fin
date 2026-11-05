# typed: strict

require "bigdecimal"

# Thin wrapper over the Alchemy Portfolio API. One POST returns native +
# ERC-20 token balances (with metadata and USD prices) for an address
# across up to 5 EVM networks.
class AlchemyClient
  extend T::Sig

  # Surfaced verbatim to callers (e.g. POST /alchemy/configuration/test);
  # controllers rely on this class to decide what's safe to relay.
  class Error < StandardError; end

  BASE_URL = T.let("https://api.g.alchemy.com/data/v1".freeze, String)

  # Zero address used only to exercise credentials in test_connection!.
  TEST_ADDRESS = T.let("0x0000000000000000000000000000000000000000".freeze, String)

  sig { params(api_key: T.nilable(String)).void }
  def initialize(api_key: nil)
    key = api_key.presence || AlchemyConfiguration.current.api_key.presence || ENV["ALCHEMY_API_KEY"]
    raise ArgumentError, "Alchemy API key not configured" if key.blank?

    @api_key = T.let(key, String)
  end

  # All token entries (native + ERC-20) for one address across the given
  # networks, following pageKey pagination. Each entry is the raw API hash:
  # network, tokenAddress (nil for native), tokenBalance (hex string),
  # tokenMetadata {decimals, symbol, name, logo}, tokenPrices [{currency, value}].
  sig { params(address: String, networks: T::Array[String]).returns(T::Array[T.untyped]) }
  def tokens_by_address(address, networks:)
    tokens   = T.let([], T::Array[T.untyped])
    page_key = T.let(nil, T.nilable(String))

    loop do
      body = {
        addresses:           [ { address: address, networks: networks } ],
        withMetadata:        true,
        withPrices:          true,
        includeNativeTokens: true
      }
      body[:pageKey] = page_key if page_key

      data = post("assets/tokens/by-address", body).fetch("data", {})
      tokens.concat(Array(data["tokens"]))
      page_key = data["pageKey"].presence
      break unless page_key
    end

    tokens
  end

  sig { void }
  def test_connection!
    tokens_by_address(TEST_ADDRESS, networks: [ "eth-mainnet" ])
    nil
  end

  # Raw balance strings arrive hex-encoded ("0x...") in the token's smallest
  # unit; convert to a whole-token BigDecimal via the token's decimals.
  sig { params(raw: T.nilable(String), decimals: T.nilable(Integer)).returns(BigDecimal) }
  def self.to_quantity(raw, decimals)
    str = raw.to_s
    return BigDecimal(0) if str.blank?

    base = str.start_with?("0x") ? str[2..].to_s.to_i(16) : str.to_i
    T.cast(BigDecimal(base) / (10**(decimals || 0)), BigDecimal)
  end

  private

  sig { params(path: String, body: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def post(path, body)
    # read_timeout stays at 30s — the portfolio call returns whole multi-chain
    # wallets and can legitimately be slow.
    HttpJson.request(:post, URI("#{BASE_URL}/#{@api_key}/#{path}"),
                     error: Error, label: "Alchemy", body: body, read_timeout: 30,
                     headers: { "Content-Type" => "application/json", "Accept" => "application/json" },
                     detail: ->(response) { Alchemy::ErrorMessage.from(response) })
  end
end
