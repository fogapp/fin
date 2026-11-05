require "rails_helper"

RSpec.describe MarketData::DailyStats do
  let(:security) { create(:security) }

  it "returns an empty hash for no ids" do
    expect(described_class.call([])).to eq({})
  end

  it "builds a sparkline and day change from recent closes" do
    create(:market_price, security: security, date: Date.current - 2, close: 100, adjusted_close: 100)
    create(:market_price, security: security, date: Date.current - 1, close: 105, adjusted_close: 105)

    stat = described_class.call([ security.id ])[security.id]
    expect(stat.spark).to eq([ 100.0, 105.0 ])
    expect(stat.day_change_pct).to eq(5.0)
    expect(stat.last_close).to eq(105.0)
    expect(stat.last_date).to eq(Date.current - 1)
  end

  it "prefers the spot quote's 24h change when present" do
    create(:market_price, security: security, date: Date.current - 2, close: 100, adjusted_close: 100)
    create(:market_price, security: security, date: Date.current - 1, close: 105, adjusted_close: 105)
    create(:instrument_quote, security: security, change_pct_24h: -3.25)

    stat = described_class.call([ security.id ])[security.id]
    expect(stat.day_change_pct).to eq(-3.25)
  end

  it "caps the sparkline at 30 points" do
    40.times do |i|
      create(:market_price, security: security, date: Date.current - i, close: 100 + i, adjusted_close: 100 + i)
    end

    stat = described_class.call([ security.id ])[security.id]
    expect(stat.spark.size).to eq(30)
    expect(stat.spark.last).to eq(100.0) # most recent close
  end

  it "leaves day change nil with a single close and no quote" do
    create(:market_price, security: security, date: Date.current - 1, close: 100, adjusted_close: 100)

    stat = described_class.call([ security.id ])[security.id]
    expect(stat.day_change_pct).to be_nil
  end
end
