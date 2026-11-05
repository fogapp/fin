require "rails_helper"

RSpec.describe MarketData::CustodianPrices do
  let(:bond)  { create(:security, :without_ticker, name: "San Fran Ca 4.0% 07/01/27", instrument_class: "bond") }
  let(:stock) { create(:security, ticker: "AAPL", instrument_class: "equity") }
  let(:today) { Date.current }

  before { allow(AlphaVantage).to receive(:configured?).and_return(true) }

  describe ".eligible?" do
    it "prices an instrument no provider can route (no ticker, unpriceable class)" do
      expect(described_class.eligible?(bond)).to be(true)
    end

    it "leaves a routable ticker to its market provider" do
      expect(described_class.eligible?(stock)).to be(false)
    end

    it "takes over when the pinned provider keeps failing and has no recent closes" do
      InstrumentDataLink.create!(security: stock, capability: MarketData::Capability::Candles,
                                    provider: MarketData::Provider::AlphaVantage, consecutive_failures: 3)
      expect(described_class.eligible?(stock)).to be(true)
    end

    it "takes over when the pinned link is disabled" do
      InstrumentDataLink.create!(security: stock, capability: MarketData::Capability::Candles,
                                    provider: MarketData::Provider::AlphaVantage, disabled: true)
      expect(described_class.eligible?(stock)).to be(true)
    end

    it "never competes with a recent provider close" do
      InstrumentDataLink.create!(security: bond, capability: MarketData::Capability::Candles,
                                    provider: MarketData::Provider::AlphaVantage, disabled: true)
      create(:candle, security: bond, date: today - 2, source: "alpha_vantage")
      expect(described_class.eligible?(bond)).to be(false)
    end
  end

  describe ".record!" do
    it "writes a close-only custodian candle and its legacy copy, as quoted" do
      expect(described_class.record!(bond, date: today, price: BigDecimal("100.0404"))).to be(true)

      candle = Candle.find_by!(security: bond, date: today)
      expect(candle).to have_attributes(source: "custodian", close: BigDecimal("100.0404"),
                                        adjusted_close: BigDecimal("100.0404"), open: nil)
      expect(MarketPrice.find_by!(security: bond, date: today).close).to eq(BigDecimal("100.0404"))
    end

    it "updates its own close on a same-day re-sync" do
      described_class.record!(bond, date: today, price: BigDecimal("100"))
      described_class.record!(bond, date: today, price: BigDecimal("101"))
      expect(Candle.where(security: bond).pluck(:close)).to eq([ BigDecimal("101") ])
    end

    it "never replaces a provider's close for the same day" do
      create(:candle, security: bond, date: today - 30, close: 99, source: "alpha_vantage")
      create(:candle, security: bond, date: today, close: 98, adjusted_close: 98, source: "alpha_vantage")
      allow(described_class).to receive(:eligible?).and_return(true)

      expect(described_class.record!(bond, date: today, price: BigDecimal("101"))).to be(false)
      expect(Candle.find_by!(security: bond, date: today)).to have_attributes(source: "alpha_vantage", close: 98)
    end

    it "doesn't overwrite a legacy-only provider price either" do
      create(:market_price, security: bond, date: today, close: 97)
      expect(described_class.record!(bond, date: today, price: BigDecimal("101"))).to be(false)
      expect(MarketPrice.find_by!(security: bond, date: today).close).to eq(97)
    end

    it "yields to a later provider write for the same day" do
      described_class.record!(bond, date: today, price: BigDecimal("101"))
      MarketData::CandleWriter.write!(bond, [ { date: today, close: BigDecimal("99.5"), adjusted_close: BigDecimal("99.5") } ],
                                      source: "tiingo")
      expect(Candle.find_by!(security: bond, date: today)).to have_attributes(source: "tiingo", close: BigDecimal("99.5"))
    end

    it "skips zero or missing prices and routable instruments" do
      expect(described_class.record!(bond, date: today, price: BigDecimal("0"))).to be(false)
      expect(described_class.record!(bond, date: today, price: nil)).to be(false)
      expect(described_class.record!(stock, date: today, price: BigDecimal("190"))).to be(false)
      expect(Candle.count).to eq(0)
    end

    it "remembers that a bond quotes per 100 of face" do
      described_class.record!(bond, date: today, price: BigDecimal("100.0404"),
                                    quantity: BigDecimal("25000"), market_value: BigDecimal("25010.09"))
      expect(bond.reload.quoted_per_hundred?).to be(true)
    end

    it "doesn't mark a per-unit instrument" do
      fund = create(:security, :without_ticker, name: "Iif Private Investors, LLC", instrument_class: "other")
      described_class.record!(fund, date: today, price: BigDecimal("1.0064"),
                                    quantity: BigDecimal("350000"), market_value: BigDecimal("352250.5"))
      expect(fund.reload.quoted_per_hundred?).to be(false)
    end
  end

  describe MarketData::CustodianPriceBackfill do
    let(:account) { create(:account) }

    it "seeds closes from every surviving snapshot date, idempotently" do
      create(:position_snapshot, account: account, security: bond, as_of_date: today - 60,
                                 quantity: 25_000, price: 101.0, market_value: 25_250)
      create(:position_snapshot, account: account, security: bond, as_of_date: today,
                                 quantity: 25_000, price: 100.04, market_value: 25_010)
      create(:position_snapshot, account: account, security: stock, as_of_date: today,
                                 quantity: 10, price: 190, market_value: 1900)

      expect(described_class.run).to eq(securities: 1, closes: 2)
      expect(Candle.where(security: bond).order(:date).pluck(:close)).to eq([ BigDecimal("101"), BigDecimal("100.04") ])
      expect(Candle.where(security: stock)).to be_empty
      expect(bond.reload.quoted_per_hundred?).to be(true)

      expect { described_class.run }.not_to change(Candle, :count)
    end
  end
end
