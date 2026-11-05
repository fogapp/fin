require "rails_helper"

RSpec.describe MarketData::LegacyCandleBackfill do
  let(:security) { create(:security, ticker: "VTI") }

  it "fills only the dates the candle store is missing, and is safe to rerun" do
    MarketPrice.create!(security: security, date: Date.new(2020, 1, 2), close: 50, volume: 7)
    MarketPrice.create!(security: security, date: Date.new(2020, 1, 3), close: 51)
    MarketPrice.create!(security: security, date: Date.new(2020, 1, 6), close: nil)
    Candle.create!(security: security, date: Date.new(2020, 1, 3), close: 99, adjusted_close: 99,
                   currency: "USD", source: "tiingo")

    expect(described_class.uncovered_count).to eq(1)
    expect(described_class.run).to eq(1)
    expect(described_class.run).to eq(0)

    backfilled = Candle.find_by!(security_id: security.id, date: Date.new(2020, 1, 2))
    expect([ backfilled.close, backfilled.volume, backfilled.source ]).to eq([ 50, 7, "legacy_market_prices" ])
    expect(Candle.find_by!(security_id: security.id, date: Date.new(2020, 1, 3)).close).to eq(99)
    expect(described_class.uncovered_count).to eq(0)
  end
end
