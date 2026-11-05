require "rails_helper"

RSpec.describe MarketData::CandleWriter do
  let(:security) { create(:security, ticker: "AAPL") }
  let(:day)      { Date.new(2026, 7, 17) }

  it "writes candles and their legacy copy, storing close as adjusted when unadjusted" do
    written = described_class.write!(security, [ { date: day, open: 1, high: 3, low: 1, close: 2, volume: 10 } ],
                                     source: "tiingo", adjusted: false)

    expect(written).to eq(1)
    candle = Candle.find_by!(security_id: security.id, date: day)
    expect([ candle.open, candle.close, candle.adjusted_close, candle.source ]).to eq([ 1, 2, 2, "tiingo" ])
    expect(MarketPrice.find_by!(security_id: security.id, date: day).adjusted_close).to eq(2)
  end

  it "never blanks OHLC another source stored when a close-only row lands on the same day" do
    described_class.write!(security, [ { date: day, open: 1, high: 3, low: 1, close: 2, volume: 10 } ],
                           source: "tiingo", adjusted: false)
    described_class.write!(security, [ { date: day, close: 2.5 } ], source: "coin_market_cap", adjusted: false)

    candle = Candle.find_by!(security_id: security.id, date: day)
    expect([ candle.open, candle.high, candle.close, candle.source ]).to eq([ 1, 3, 2.5, "coin_market_cap" ])
  end

  it "extracts splits and dividends from an adjusted series" do
    described_class.write_corporate_actions!(
      security, [ { date: day, split_coefficient: 4, dividend_amount: 0.25 } ], source: "alpha_vantage"
    )

    expect(CorporateAction.where(security_id: security.id).pluck(:kind)).to contain_exactly("split", "dividend")
  end
end
