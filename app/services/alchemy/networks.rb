# typed: strict

module Alchemy
  # Per-network quirk table for the transaction-sync pipeline. Network slugs
  # match AlchemyWallet::SUPPORTED_NETWORKS ("eth-mainnet", ...); the Notify
  # webhook API speaks a different dialect ("ETH_MAINNET").
  module Networks
    extend T::Sig

    # getAssetTransfers rejects category "internal" outside these networks
    # with a 400, so the category set must vary per network.
    INTERNAL_SUPPORTED = T.let(%w[eth-mainnet polygon-mainnet].freeze, T::Array[String])

    # Blocks held back from the tip before ingesting, so reorgs never reach
    # the ledger. L2 blocks are ~2s, so a larger count is still under a minute.
    CONFIRMATION_DEPTHS = T.let({
      "eth-mainnet"     => 12,
      "polygon-mainnet" => 60,
      "base-mainnet"    => 30,
      "arb-mainnet"     => 30,
      "opt-mainnet"     => 30
    }.freeze, T::Hash[String, Integer])
    DEFAULT_CONFIRMATION_DEPTH = 30

    sig { params(network: String).returns(T::Array[String]) }
    def self.categories_for(network)
      base = %w[external erc20]
      INTERNAL_SUPPORTED.include?(network) ? base + %w[internal] : base
    end

    sig { params(network: String).returns(Integer) }
    def self.confirmation_depth(network)
      CONFIRMATION_DEPTHS.fetch(network, DEFAULT_CONFIRMATION_DEPTH)
    end

    # "eth-mainnet" → "ETH_MAINNET" (Notify API request format)
    sig { params(slug: String).returns(String) }
    def self.to_webhook(slug)
      slug.tr("-", "_").upcase
    end
  end
end
