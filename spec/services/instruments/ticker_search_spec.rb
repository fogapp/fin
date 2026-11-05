require "rails_helper"

RSpec.describe Instruments::TickerSearch do
  subject(:search) { described_class.new }

  let(:client) { instance_double(AlphaVantage::Client) }

  def match(ticker:, name: ticker, type: "Equity")
    { ticker: ticker, name: name, security_type: type, region: "United States",
      currency: "USD", match_score: 1.0 }
  end

  around do |example|
    original = ENV["ALPHA_VANTAGE_API_KEY"]
    ENV["ALPHA_VANTAGE_API_KEY"] = "test-key"
    example.run
  ensure
    original ? ENV["ALPHA_VANTAGE_API_KEY"] = original : ENV.delete("ALPHA_VANTAGE_API_KEY")
  end

  before do
    allow(AlphaVantage::Client).to receive(:new).and_return(client)
  end

  it "returns provider matches with a mapped instrument class" do
    allow(client).to receive(:symbol_search).with("NV").and_return([
      match(ticker: "NVDA", name: "NVIDIA Corporation"),
      match(ticker: "NVQ", name: "Some ETF", type: "ETF")
    ])

    results = search.call("NV")
    expect(results.map { |r| r[:ticker] }).to eq(%w[NVDA NVQ])
    expect(results.first[:instrument_class]).to eq(Instruments::InstrumentClass::Equity)
    expect(results.last[:instrument_class]).to eq(Instruments::InstrumentClass::Etf)
  end

  it "excludes tickers that already have a Security row" do
    create(:security, ticker: "NVDA")
    allow(client).to receive(:symbol_search).and_return([
      match(ticker: "NVDA"), match(ticker: "NVDL")
    ])

    expect(search.call("NVD").map { |r| r[:ticker] }).to eq([ "NVDL" ])
  end

  it "ranks the exact symbol first, then US listings, over provider order" do
    allow(client).to receive(:symbol_search).and_return([
      match(ticker: "NVD.DEX", name: "NVIDIA (XETRA)").merge(region: "XETRA", match_score: 0.95),
      match(ticker: "NVDL", name: "GraniteShares 2x Long NVDA", type: "ETF").merge(match_score: 0.6),
      match(ticker: "NVDA34.SAO", name: "NVIDIA BDR").merge(region: "Brazil/Sao Paolo", match_score: 0.7),
      match(ticker: "NVDA", name: "NVIDIA Corporation").merge(match_score: 0.9)
    ])

    # Exact match first; NVDL is the only other US listing; foreign listings
    # trail in match-score order.
    expect(search.call("nvda").map { |r| r[:ticker] }).to eq(%w[NVDA NVDL NVD.DEX NVDA34.SAO])
  end

  it "drops untrackable types (currencies, indices)" do
    allow(client).to receive(:symbol_search).and_return([
      match(ticker: "USDEUR", type: "Currency"),
      match(ticker: "NVDA")
    ])

    expect(search.call("NV").map { |r| r[:ticker] }).to eq([ "NVDA" ])
  end

  it "returns [] for short queries without calling the provider" do
    expect(client).not_to receive(:symbol_search)
    expect(search.call("N")).to eq([])
    expect(search.call("  ")).to eq([])
  end

  it "returns [] when the provider key is not configured" do
    ENV.delete("ALPHA_VANTAGE_API_KEY")
    expect(client).not_to receive(:symbol_search)
    expect(search.call("NVDA")).to eq([])
  end

  it "swallows provider errors and returns []" do
    allow(client).to receive(:symbol_search).and_raise(AlphaVantage::RateLimitError, "throttled")
    expect(search.call("NVDA")).to eq([])
  end
end
