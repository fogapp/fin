require "rails_helper"

RSpec.describe MarketData::Providers::Tiingo do
  before { allow(Tiingo).to receive(:api_key).and_return("test-key") }

  describe "equities" do
    let(:security) { create(:security, ticker: "AAPL", instrument_class: "equity") }
    let(:link) do
      InstrumentDataLink.create!(security: security, capability: MarketData::Capability::Candles,
                                 provider: MarketData::Provider::Tiingo)
    end

    def daily_body
      [
        { "date" => "2026-07-16T00:00:00.000Z", "open" => 210.0, "high" => 214.0, "low" => 209.0,
          "close" => 212.0, "adjClose" => 212.0, "volume" => 1000, "divCash" => 0.0, "splitFactor" => 1.0 },
        { "date" => "2026-07-17T00:00:00.000Z", "open" => 212.0, "high" => 216.0, "low" => 211.0,
          "close" => 215.0, "adjClose" => 214.5, "volume" => 1200, "divCash" => 0.25, "splitFactor" => 2.0 }
      ].to_json
    end

    it "writes adjusted candles, corporate actions, and legacy market_prices" do
      stub_request(:get, %r{api\.tiingo\.com/tiingo/daily/aapl/prices})
        .to_return(status: 200, body: daily_body)

      expect(described_class.new.sync_candles(security, link)).to eq(2)

      candle = Candle.find_by(security_id: security.id, date: Date.new(2026, 7, 17))
      expect(candle.close).to eq(215)
      expect(candle.adjusted_close).to eq(214.5)
      expect(candle.source).to eq("tiingo")

      actions = CorporateAction.where(security_id: security.id)
      expect(actions.find_by(kind: "dividend", ex_date: Date.new(2026, 7, 17)).amount).to eq(0.25)
      expect(actions.find_by(kind: "split", ex_date: Date.new(2026, 7, 17)).ratio).to eq(2)
      expect(MarketPrice.where(security_id: security.id).count).to eq(2)
    end

    it "requests the full history only when asked" do
      stub = stub_request(:get, %r{api\.tiingo\.com/tiingo/daily/aapl/prices})
        .to_return(status: 200, body: "[]")

      described_class.new.sync_candles(security, link, full: true)
      expect(stub).to have_been_requested
      expect(WebMock).to have_requested(:get, %r{tiingo/daily/aapl/prices$})
    end

    it "raises RateLimitError on HTTP 429" do
      stub_request(:get, %r{api\.tiingo\.com/tiingo/daily/aapl/prices})
        .to_return(status: 429, body: "")

      expect { described_class.new.sync_candles(security, link) }
        .to raise_error(Tiingo::RateLimitError)
    end
  end

  describe "crypto" do
    let(:security) { create(:security, ticker: "BTC", instrument_class: "crypto") }
    let(:link) do
      InstrumentDataLink.create!(security: security, capability: MarketData::Capability::Candles,
                                 provider: MarketData::Provider::Tiingo)
    end

    def crypto_body
      [ { "ticker" => "btcusd", "priceData" => [
        { "date" => "2026-07-17T00:00:00+00:00", "open" => 118_000.0, "high" => 120_500.0,
          "low" => 117_200.0, "close" => 119_800.0, "volume" => 5_000 }
      ] } ].to_json
    end

    it "writes OHLCV candles and resolves the usd pair into provider_ref" do
      stub_request(:get, %r{api\.tiingo\.com/tiingo/crypto/prices})
        .with(query: hash_including("tickers" => "btcusd", "resampleFreq" => "1day"))
        .to_return(status: 200, body: crypto_body)

      expect(described_class.new.sync_candles(security, link)).to eq(1)

      candle = Candle.find_by(security_id: security.id, date: Date.new(2026, 7, 17))
      expect(candle.open).to eq(118_000)
      expect(candle.adjusted_close).to eq(119_800)
      expect(candle.source).to eq("tiingo")
      expect(link.reload.provider_ref).to eq("btcusd")
      expect(CorporateAction.where(security_id: security.id)).to be_empty
    end
  end
end
