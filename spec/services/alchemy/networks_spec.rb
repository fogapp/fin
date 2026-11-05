require "rails_helper"

RSpec.describe Alchemy::Networks do
  it "includes internal only where Alchemy supports it" do
    expect(described_class.categories_for("eth-mainnet")).to contain_exactly("external", "erc20", "internal")
    expect(described_class.categories_for("polygon-mainnet")).to include("internal")
    expect(described_class.categories_for("base-mainnet")).to contain_exactly("external", "erc20")
    expect(described_class.categories_for("arb-mainnet")).not_to include("internal")
  end

  it "has a confirmation depth for every supported wallet network" do
    AlchemyWallet::SUPPORTED_NETWORKS.each do |network|
      expect(described_class.confirmation_depth(network)).to be > 0
    end
  end

  it "formats network slugs as Notify API names" do
    expect(described_class.to_webhook("eth-mainnet")).to eq("ETH_MAINNET")
    expect(described_class.to_webhook("base-mainnet")).to eq("BASE_MAINNET")
  end
end
