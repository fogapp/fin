require "rails_helper"

RSpec.describe MarketData::Router do
  let(:equity) { create(:security, ticker: "AAPL", instrument_class: "equity") }
  let(:coin)   { create(:security, ticker: "BTC", instrument_class: "crypto") }

  def configure!(tiingo: false, alpha_vantage: true)
    allow(Tiingo).to receive(:configured?).and_return(tiingo)
    allow(AlphaVantage).to receive(:configured?).and_return(alpha_vantage)
  end

  describe ".link_for" do
    it "pins equities to Alpha Vantage and crypto to CoinGecko when Tiingo is not configured" do
      configure!(tiingo: false)

      expect(described_class.link_for(equity, MarketData::Capability::Candles).provider)
        .to eq(MarketData::Provider::AlphaVantage)
      expect(described_class.link_for(coin, MarketData::Capability::Candles).provider)
        .to eq(MarketData::Provider::CoinGecko)
    end

    it "prefers Tiingo for both equities and crypto when configured" do
      configure!(tiingo: true)

      expect(described_class.link_for(equity, MarketData::Capability::Candles).provider)
        .to eq(MarketData::Provider::Tiingo)
      expect(described_class.link_for(coin, MarketData::Capability::Candles).provider)
        .to eq(MarketData::Provider::Tiingo)
    end

    it "falls back to the last candidate when nothing is configured" do
      configure!(tiingo: false, alpha_vantage: false)

      expect(described_class.link_for(equity, MarketData::Capability::Candles).provider)
        .to eq(MarketData::Provider::AlphaVantage)
    end

    it "re-pins an existing link whose provider integration was deleted" do
      configure!(tiingo: true)
      link = described_class.link_for(coin, MarketData::Capability::Candles)
      expect(link.provider).to eq(MarketData::Provider::Tiingo)

      configure!(tiingo: false)
      expect(described_class.link_for(coin, MarketData::Capability::Candles).provider)
        .to eq(MarketData::Provider::CoinGecko)
    end

    it "keeps an available pinned provider even when it is not the top preference" do
      configure!(tiingo: false)
      link = described_class.link_for(equity, MarketData::Capability::Candles)
      expect(link.provider).to eq(MarketData::Provider::AlphaVantage)

      configure!(tiingo: true)
      # link_for alone does not churn healthy pins; that's repin_defaults!'s job.
      expect(described_class.link_for(equity, MarketData::Capability::Candles).provider)
        .to eq(MarketData::Provider::AlphaVantage)
    end
  end

  describe ".repin_defaults!" do
    it "moves default-routed links to the newly preferred provider and resets provider state" do
      configure!(tiingo: false)
      link = described_class.link_for(coin, MarketData::Capability::Candles)
      link.update!(provider_ref: "bitcoin", consecutive_failures: 3, last_error: "boom")

      configure!(tiingo: true)
      described_class.repin_defaults!

      link.reload
      expect(link.provider).to eq(MarketData::Provider::Tiingo)
      expect(link.provider_ref).to be_nil
      expect(link.consecutive_failures).to eq(0)
      expect(link.last_error).to be_nil
    end

    it "leaves links alone when the preferred provider is unchanged" do
      configure!(tiingo: true)
      link = described_class.link_for(equity, MarketData::Capability::Candles)
      link.update!(provider_ref: "keep-me")

      described_class.repin_defaults!
      expect(link.reload.provider_ref).to eq("keep-me")
    end
  end

  describe ".secondary_provider" do
    it "returns the runner-up configured provider for cross-checking" do
      configure!(tiingo: true)

      expect(described_class.secondary_provider(equity, MarketData::Capability::Candles,
                                                MarketData::Provider::Tiingo))
        .to eq(MarketData::Provider::AlphaVantage)
      expect(described_class.secondary_provider(coin, MarketData::Capability::Candles,
                                                MarketData::Provider::Tiingo))
        .to eq(MarketData::Provider::CoinGecko)
    end

    it "returns nil when no other candidate is configured" do
      configure!(tiingo: false, alpha_vantage: false)

      expect(described_class.secondary_provider(equity, MarketData::Capability::Candles,
                                                MarketData::Provider::AlphaVantage)).to be_nil
    end
  end
end
