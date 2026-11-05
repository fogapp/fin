require "rails_helper"

RSpec.describe MarketData::CrossCheck do
  let(:household) { create(:household) }
  let(:security)  { create(:security, ticker: "AAPL", instrument_class: "equity") }

  before do
    allow(Tiingo).to receive(:configured?).and_return(true)
    allow(Tiingo).to receive(:api_key).and_return("tiingo-key")
    allow(AlphaVantage).to receive(:configured?).and_return(true)
    allow(AlphaVantage).to receive(:api_key).and_return("av-key")
    SecurityWatch.create!(security: security, household: household)
    InstrumentDataLink.create!(security: security, capability: MarketData::Capability::Candles,
                               provider: MarketData::Provider::Tiingo)
  end

  def store_candle(date, close)
    create(:candle, security: security, date: date, close: close, adjusted_close: close, source: "tiingo")
  end

  def stub_alpha_vantage_daily(dates_to_closes)
    series = dates_to_closes.to_h do |date, close|
      [ date.iso8601, { "1. open" => close.to_s, "2. high" => close.to_s, "3. low" => close.to_s,
                        "4. close" => close.to_s, "5. volume" => "1000" } ]
    end
    stub_request(:get, %r{www\.alphavantage\.co/query})
      .with(query: hash_including("function" => "TIME_SERIES_DAILY"))
      .to_return(status: 200, body: { "Time Series (Daily)" => series }.to_json)
  end

  it "raises an Issue for watching households when the second source disagrees" do
    day = Date.current - 2
    store_candle(day, 200.0)
    stub_alpha_vantage_daily(day => 190.0) # ~5% apart, above the 0.5% band

    result = described_class.run(pace: false)

    expect(result.mismatched).to eq(1)
    issue = Issue.unscoped.find_by(key: "market_data.cross_check.#{security.id}")
    expect(issue).to be_present
    expect(issue.household_id).to eq(household.id)
    expect(issue.title).to include("AAPL")
    expect(issue.dismissed_at).to be_nil
  end

  it "auto-resolves the Issue once the sources agree again" do
    day = Date.current - 2
    store_candle(day, 200.0)
    Current.set(household: household) do
      Issue.raise_once!(key: "market_data.cross_check.#{security.id}", title: "old", source: "market_data.cross_check")
    end
    stub_alpha_vantage_daily(day => 200.4) # within 0.5%

    result = described_class.run(pace: false)

    expect(result.clean).to eq(1)
    expect(Issue.unscoped.find_by(key: "market_data.cross_check.#{security.id}").dismissed_at).to be_present
  end

  it "ignores today's in-flight candle" do
    store_candle(Date.current, 200.0)
    stub_alpha_vantage_daily(Date.current => 150.0)

    result = described_class.run(pace: false)

    expect(result.mismatched).to eq(0)
    expect(Issue.unscoped.where(key: "market_data.cross_check.#{security.id}")).to be_empty
  end

  it "skips instruments with no second configured provider" do
    allow(AlphaVantage).to receive(:configured?).and_return(false)
    store_candle(Date.current - 2, 200.0)

    result = described_class.run(pace: false)

    expect(result.checked).to eq(0)
    expect(result.skipped).to eq(1)
  end

  it "survives a provider error on one instrument and keeps a clean result" do
    day = Date.current - 2
    store_candle(day, 200.0)
    stub_request(:get, %r{www\.alphavantage\.co/query}).to_return(status: 500, body: "boom")

    result = described_class.run(pace: false)

    expect(result.skipped).to eq(1)
    expect(result.mismatched).to eq(0)
  end
end
