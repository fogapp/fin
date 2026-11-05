require "rails_helper"

RSpec.describe MarketData::OhlcvSeries do
  let(:security) { create(:security) }

  describe ".rows" do
    it "returns ascending OHLCV rows from legacy market prices" do
      create(:market_price, security: security, date: Date.new(2026, 1, 6),
             open: 10, high: 12, low: 9, close: 11, adjusted_close: 11, volume: 100)
      create(:market_price, security: security, date: Date.new(2026, 1, 5),
             open: 9, high: 10, low: 8, close: 10, adjusted_close: 10, volume: 200)

      rows = described_class.rows(security)
      expect(rows.map(&:date)).to eq([ Date.new(2026, 1, 5), Date.new(2026, 1, 6) ])
      expect(rows.last.to_h).to include(open: 10.0, high: 12.0, low: 9.0, close: 11.0, volume: 100)
    end

    it "prefers candles over legacy rows on the same date" do
      date = Date.new(2026, 1, 5)
      create(:market_price, security: security, date: date, close: 10, adjusted_close: 10)
      create(:candle, security: security, date: date, close: 99, adjusted_close: 99)

      rows = described_class.rows(security)
      expect(rows.size).to eq(1)
      expect(rows.first.close).to eq(99.0)
    end

    it "back-adjusts open/high/low by the split adjustment factor" do
      # Pre-split candle: raw close 100, adjusted 25 (a later 4:1 split).
      create(:candle, security: security, date: Date.new(2025, 6, 2),
             open: 96, high: 104, low: 92, close: 100, adjusted_close: 25)

      row = described_class.rows(security).first
      expect(row.open).to eq(24.0)
      expect(row.high).to eq(26.0)
      expect(row.low).to eq(23.0)
      expect(row.close).to eq(25.0)
    end

    it "keeps nil open/high/low for close-only sources" do
      create(:candle, security: security, date: Date.new(2026, 1, 5),
             open: nil, high: nil, low: nil, close: 50, adjusted_close: nil, volume: nil)

      row = described_class.rows(security).first
      expect(row.open).to be_nil
      expect(row.close).to eq(50.0)
    end

    it "windows by from/to" do
      create(:market_price, security: security, date: Date.new(2026, 1, 1))
      create(:market_price, security: security, date: Date.new(2026, 1, 15))

      rows = described_class.rows(security, from: Date.new(2026, 1, 10))
      expect(rows.map(&:date)).to eq([ Date.new(2026, 1, 15) ])
    end
  end

  describe ".weekly" do
    it "aggregates daily rows into ISO-week candles" do
      # Mon..Fri of one ISO week.
      rows = (0..4).map do |i|
        described_class::Row.new(
          date: Date.new(2026, 1, 5) + i, # 2026-01-05 is a Monday
          open: 10.0 + i, high: 20.0 + i, low: 5.0 - i, close: 15.0 + i, volume: 100
        )
      end

      weekly = described_class.weekly(rows)
      expect(weekly.size).to eq(1)
      candle = weekly.first
      expect(candle.date).to eq(Date.new(2026, 1, 9))
      expect(candle.open).to eq(10.0)
      expect(candle.high).to eq(24.0)
      expect(candle.low).to eq(1.0)
      expect(candle.close).to eq(19.0)
      expect(candle.volume).to eq(500)
    end

    it "splits rows across ISO week boundaries" do
      rows = [
        described_class::Row.new(date: Date.new(2026, 1, 9), open: 1.0, high: 1.0, low: 1.0, close: 1.0, volume: 1),
        described_class::Row.new(date: Date.new(2026, 1, 12), open: 2.0, high: 2.0, low: 2.0, close: 2.0, volume: 1)
      ]
      expect(described_class.weekly(rows).size).to eq(2)
    end
  end
end
