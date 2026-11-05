require "rails_helper"
require "stringio"

RSpec.describe Importers::HoldingsCsv do
  let(:csv_import) { create(:csv_import) }
  let(:broker)     { create(:broker, name: "Parametric") }
  let(:account)    { create(:account, broker: broker) }

  def header
    "Ticker,CUSIP,Description,Asset Class,Pricing Date,Acquisition Date,Quantity,Price,Value,Cost,Unit Cost,Unrealized G/L Amt.,Unrealized Gain/Loss (%),Accrued Income,Est. Annual Income,Dividend Yield,Asset Strategy,Asset Strategy Detail"
  end

  def csv_with(rows)
    StringIO.new(([ header ] + rows).join("\n"))
  end

  def holdings_row(ticker: "AAPL", cusip: "037833100", desc: "APPLE INC",
                   asset_class: "Equity", price_date: "12/31/2025",
                   quantity: "10", price: "150.00", value: "1500.00", cost: "1000.00")
    [ ticker, cusip, desc, asset_class, price_date, "01/15/2024",
     quantity, price, value, cost, "100.00", "500.00", "50.00",
     "0", "20.00", "0.0133", "Domestic Equity", "Large Cap" ].join(",")
  end

  describe "#call" do
    it "records the statement price as a custodian close for an unlisted holding" do
      rows = [ holdings_row(ticker: "", cusip: "072024YP1", desc: "Bay Area Ca Toll Auth to 5% 04/01/29",
                            asset_class: "Fixed Income", quantity: "50000", price: "104.613", value: "52306.51") ]
      described_class.new(source: csv_with(rows), csv_import: csv_import, target_account: account).call

      bond = Security.find_by!(cusip: "072024YP1")
      expect(Candle.where(security: bond).pluck(:date, :close, :source))
        .to eq([ [ Date.new(2025, 12, 31), BigDecimal("104.613"), "custodian" ] ])
      expect(bond.quoted_per_hundred?).to be(true)
    end

    it "imports a holding row" do
      importer = described_class.new(source: csv_with([ holdings_row ]), csv_import: csv_import, target_account: account)

      result = importer.call

      expect(result.imported).to eq(1)
      expect(result.errors).to be_empty

      sec = Security.find_by(ticker: "AAPL")
      expect(sec).to be_present
      expect(sec.cusip).to eq("037833100")
      expect(sec.name).to eq("APPLE INC")

      snap = PositionSnapshot.first
      expect(snap.account).to eq(account)
      expect(snap.security).to eq(sec)
      expect(snap.as_of_date).to eq(Date.new(2025, 12, 31))
      expect(snap.quantity).to eq(BigDecimal("10"))
      expect(snap.price).to eq(BigDecimal("150"))
      expect(snap.market_value).to eq(BigDecimal("1500"))
      expect(snap.cost_basis).to eq(BigDecimal("1000"))
      expect(snap.asset_class).to eq("Equity")
    end

    it "is idempotent — re-importing the same row is a skip" do
      described_class.new(source: csv_with([ holdings_row ]), csv_import: csv_import, target_account: account).call
      result = described_class.new(source: csv_with([ holdings_row ]), csv_import: create(:csv_import), target_account: account).call

      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(1)
      expect(PositionSnapshot.count).to eq(1)
    end

    it "updates an existing snapshot when the row hash changes" do
      described_class.new(source: csv_with([ holdings_row ]), csv_import: csv_import, target_account: account).call

      changed = holdings_row(price: "200", value: "2000")
      described_class.new(source: csv_with([ changed ]), csv_import: create(:csv_import), target_account: account).call

      expect(PositionSnapshot.count).to eq(1)
      expect(PositionSnapshot.first.price).to eq(BigDecimal("200"))
    end

    it "skips rows with no ticker and no CUSIP" do
      empty = holdings_row(ticker: "", cusip: "")
      importer = described_class.new(source: csv_with([ empty, holdings_row ]), csv_import: csv_import, target_account: account)

      expect(importer.call.imported).to eq(1)
      expect(PositionSnapshot.count).to eq(1)
    end

    it "errors if Pricing Date and As of are both missing" do
      bad = holdings_row(price_date: "")
      result = described_class.new(source: csv_with([ bad ]), csv_import: csv_import, target_account: account).call

      expect(result.imported).to eq(0)
      expect(result.errors.size).to eq(1)
      expect(result.errors.first[:error]).to match(/no as_of/)
    end

    context "when target_account is missing" do
      it "uses the broker's first account when default_broker is set" do
        importer = described_class.new(source: csv_with([ holdings_row ]), csv_import: csv_import,
                                       default_broker: broker.name, target_account: nil)
        # account is auto-created via factory; bind it to the broker
        account # touch
        importer.call

        expect(PositionSnapshot.count).to eq(1)
      end

      it "raises if no broker is given either" do
        importer = described_class.new(source: csv_with([ holdings_row ]), csv_import: csv_import,
                                       default_broker: nil, target_account: nil)

        expect { importer.call }.to raise_error(/Pick an account/)
        expect(csv_import.reload.status).to eq("failed")
      end

      it "raises if broker has no accounts" do
        empty_broker = create(:broker, name: "EmptyBroker")
        importer = described_class.new(source: csv_with([ holdings_row ]), csv_import: csv_import,
                                       default_broker: empty_broker.name, target_account: nil)

        expect { importer.call }.to raise_error(/no accounts yet/)
      end
    end

    it "upgrades an existing security's junk name to the cleaner Description" do
      sec = create(:security, ticker: "AAPL", cusip: "037833100", name: "")

      described_class.new(source: csv_with([ holdings_row ]), csv_import: csv_import, target_account: account).call

      expect(sec.reload.name).to eq("APPLE INC")
    end
  end
end
