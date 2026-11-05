require "rails_helper"

RSpec.describe MarketData::PriceSeries do
  let(:security) { create(:security, ticker: "VTI") }

  describe ".daily_closes" do
    it "merges candles over legacy prices per date — one fresh candle never erases history" do
      MarketPrice.create!(security: security, date: Date.new(2026, 6, 1), close: 100)
      MarketPrice.create!(security: security, date: Date.new(2026, 6, 2), close: 101)
      Candle.create!(security: security, date: Date.new(2026, 6, 2), close: 200,
                     adjusted_close: 150, currency: "USD", source: "alpha_vantage")

      closes = described_class.daily_closes(security, from: Date.new(2026, 6, 1), to: Date.new(2026, 6, 3))

      expect(closes).to eq([
        [ Date.new(2026, 6, 1), BigDecimal("100") ], # legacy fills the gap
        [ Date.new(2026, 6, 2), BigDecimal("150") ]  # candle (adjusted) wins the date
      ])
    end

    it "returns empty when nothing is priced" do
      expect(described_class.daily_closes(security)).to eq([])
    end
  end

  describe ".edge_closes_by_security" do
    before do
      MarketPrice.create!(security: security, date: Date.new(2026, 1, 2), close: 90)
      MarketPrice.create!(security: security, date: Date.new(2026, 6, 3), close: 101)
      Candle.create!(security: security, date: Date.new(2026, 6, 3), close: 200,
                     adjusted_close: 150, currency: "USD", source: "alpha_vantage")
      Candle.create!(security: security, date: Date.new(2026, 1, 5), close: 95,
                     adjusted_close: 95, currency: "USD", source: "alpha_vantage")
    end

    it "returns the newest close, candles winning a shared date" do
      expect(described_class.edge_closes_by_security([ security.id ]))
        .to eq(security.id => [ Date.new(2026, 6, 3), BigDecimal("150") ])
    end

    it "returns the first close on or after a date across both tables" do
      expect(described_class.edge_closes_by_security([ security.id ], on_or_after: Date.new(2026, 1, 1)))
        .to eq(security.id => [ Date.new(2026, 1, 2), BigDecimal("90") ])
    end
  end

  describe ".close_on" do
    it "returns the close on the date, or the nearest earlier close within the window" do
      Candle.create!(security: security, date: Date.new(2026, 6, 5), close: 120,
                     currency: "USD", source: "coin_gecko")

      expect(described_class.close_on(security, Date.new(2026, 6, 5))).to eq(120)
      expect(described_class.close_on(security, Date.new(2026, 6, 8))).to eq(120)  # weekend gap
      expect(described_class.close_on(security, Date.new(2026, 6, 20))).to be_nil  # too stale
      expect(described_class.close_on(security, Date.new(2026, 6, 4))).to be_nil   # never looks forward
    end
  end

  describe ".latest_quote" do
    it "prefers the spot quote, then candles, then legacy" do
      MarketPrice.create!(security: security, date: 3.days.ago.to_date, close: 90)
      expect(described_class.latest_quote(security).price).to eq(90)

      Candle.create!(security: security, date: 2.days.ago.to_date, close: 95,
                     currency: "USD", source: "coin_gecko")
      expect(described_class.latest_quote(security).price).to eq(95)

      InstrumentQuote.create!(security: security, price: 99, currency: "USD",
                              source: "coin_market_cap", as_of: Time.current)
      quote = described_class.latest_quote(security)
      expect(quote.price).to eq(99)
      expect(quote.age_days).to eq(0)
    end
  end
end
