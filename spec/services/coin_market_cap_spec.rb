require "rails_helper"

RSpec.describe CoinMarketCap do
  around { |ex| with_env("COINMARKETCAP_API_KEY" => nil) { ex.run } }

  describe ".api_key" do
    it "prefers the household's configured key" do
      CoinMarketCapConfiguration.create!(api_key: "household-key")

      with_env("COINMARKETCAP_API_KEY" => "env-key") do
        expect(described_class.api_key).to eq("household-key")
      end
    end

    it "falls back to ENV when the household has no key" do
      with_env("COINMARKETCAP_API_KEY" => "env-key") do
        expect(described_class.api_key).to eq("env-key")
        expect(described_class).to be_configured
      end
    end

    it "is nil (unconfigured) with neither" do
      expect(described_class.api_key).to be_nil
      expect(described_class).not_to be_configured
    end
  end

  describe ".any_configured?" do
    it "sees another household's key outside a household context" do
      other = create(:household, name: "Other")
      CoinMarketCapConfiguration.unscoped.create!(household: other, api_key: "k")

      Current.set(household: nil) { expect(described_class.any_configured?).to be(true) }
    end

    it "is true for an ENV-only key" do
      with_env("COINMARKETCAP_API_KEY" => "env-key") do
        Current.set(household: nil) { expect(described_class.any_configured?).to be(true) }
      end
    end

    it "is false with no key anywhere" do
      Current.set(household: nil) { expect(described_class.any_configured?).to be(false) }
    end
  end
end
