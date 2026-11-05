require "rails_helper"

RSpec.describe MarketData::Providers::CoinGecko do
  let(:security) { create(:security, ticker: "ETH", security_type: "Crypto") }
  let(:link) do
    InstrumentDataLink.create!(security: security, capability: MarketData::Capability::Candles,
                               provider: MarketData::Provider::CoinGecko, provider_ref: "ethereum")
  end
  let(:chart_url) { "https://api.coingecko.com/api/v3/coins/ethereum/market_chart" }

  def price_body(dates_to_prices)
    { "prices" => dates_to_prices.map { |d, p| [ d.to_time.to_i * 1000, p ] } }.to_json
  end

  it "falls back to 365 days when the public tier rejects max history (error 10012)" do
    stub_request(:get, chart_url).with(query: hash_including("days" => "max"))
      .to_return(status: 401, body: '{"error":{"status":{"error_code":10012,"error_message":"Your request exceeds the allowed time range."}}}')
    stub_request(:get, chart_url).with(query: hash_including("days" => "365"))
      .to_return(status: 200, body: price_body(Date.new(2026, 7, 10) => 2000.0))

    expect(described_class.new.sync_candles(security, link, full: true)).to eq(1)
    expect(Candle.find_by(security_id: security.id, date: Date.new(2026, 7, 10)).close).to eq(2000)
  end

  it "re-raises other errors without retrying" do
    stub_request(:get, chart_url).with(query: hash_including("days" => "max"))
      .to_return(status: 500, body: "boom")

    expect { described_class.new.sync_candles(security, link, full: true) }
      .to raise_error(CoinGecko::Client::Error, /500/)
  end

  it "does not retry non-full syncs" do
    stub = stub_request(:get, chart_url).with(query: hash_including("days" => "30"))
      .to_return(status: 401, body: '{"error_code":10012}')

    expect { described_class.new.sync_candles(security, link) }
      .to raise_error(CoinGecko::Client::Error)
    expect(stub).to have_been_requested.once
  end
end
