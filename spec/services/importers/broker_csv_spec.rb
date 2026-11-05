require "rails_helper"
require "stringio"

RSpec.describe Importers::BrokerCsv do
  let(:csv_import) { create(:csv_import) }

  def header
    [
      "Trade Date", "Post Date", "Settlement Date", "Account Name", "Account Number", "Account Type",
      "Type", "Description", "Cusip", "Ticker", "Security Type", "Local Currency",
      "Price USD", "Price Local", "Quantity", "Cost USD", "Cost Local",
      "G/L Short USD", "G/L Short Local", "G/L Long USDs", "G/L Long Local",
      "Amount USD", "Amount Local", "Income USD", "Income Local", "Balance",
      "Commissions USD", "Commissions Local", "Tran Code", "Tran Code Description",
      "Broker", "Check Number", "Tax Withheld"
    ].join(",")
  end

  def csv_with(rows)
    StringIO.new(([ header ] + rows).join("\n"))
  end

  def dividend_row(date: "12/31/2025", account: "Parametric", account_number: "...7000",
                   ticker: "MAR", cusip: "571903202", amount: "48.24")
    [
      date, date, date, account, account_number, "Invt Mgmt",
      "Dividend", "MARRIOTT INTERNATIONAL -CL A @ 0.67 PER SHARE", cusip, ticker, "", "USD",
      "0", "0", "72", "0", "0",
      "0", "0", "0", "0",
      "0", "0", amount, amount, "",
      "0", "0", "011", "DIV DOMEST",
      "", "0", ""
    ].join(",")
  end

  describe "#call" do
    it "imports a transaction row and creates broker, account, security, transaction_type" do
      importer = described_class.new(source: csv_with([ dividend_row ]), default_broker: "Parametric", csv_import: csv_import)

      result = importer.call

      expect(result.imported).to eq(1)
      expect(result.skipped).to eq(0)
      expect(result.errors).to be_empty

      expect(Broker.find_by(name: "Parametric")).to be_present
      account = Account.find_by(account_number: "...7000")
      expect(account).to be_present
      expect(account.broker.name).to eq("Parametric")

      security = Security.find_by(ticker: "MAR")
      expect(security).to be_present
      expect(security.cusip).to eq("571903202")
      expect(security.name).to eq("MARRIOTT INTERNATIONAL -CL A")

      ttype = TransactionType.find_by(code: "011")
      expect(ttype).to be_present
      expect(ttype.category).to eq("Dividend")

      txn = InvestmentTransaction.first
      expect(txn.account).to eq(account)
      expect(txn.security).to eq(security)
      expect(txn.income_usd).to eq(48.24)
    end

    it "is idempotent (duplicate runs skip already-imported rows)" do
      importer = described_class.new(source: csv_with([ dividend_row ]), default_broker: "Parametric", csv_import: csv_import)
      importer.call

      second_import = create(:csv_import)
      importer2 = described_class.new(source: csv_with([ dividend_row ]), default_broker: "Parametric", csv_import: second_import)
      result = importer2.call

      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(1)
      expect(InvestmentTransaction.count).to eq(1)
    end

    it "raises if default_broker is missing" do
      importer = described_class.new(source: csv_with([ dividend_row ]), default_broker: nil, csv_import: csv_import)

      result = importer.call

      expect(result.imported).to eq(0)
      expect(result.errors.size).to eq(1)
      expect(result.errors.first[:error]).to match(/default_broker is required/)
    end

    it "skips fully blank rows" do
      blank = ([ ",,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,," ]).first
      importer = described_class.new(source: csv_with([ blank, dividend_row ]), default_broker: "Parametric", csv_import: csv_import)

      result = importer.call

      expect(result.imported).to eq(1)
      expect(result.errors).to be_empty
    end

    it "updates the csv_import record with status, counts, and timing" do
      importer = described_class.new(source: csv_with([ dividend_row ]), default_broker: "Parametric", csv_import: csv_import)

      importer.call
      csv_import.reload

      expect(csv_import.status).to eq("completed")
      expect(csv_import.imported_count).to eq(1)
      expect(csv_import.skipped_count).to eq(0)
      expect(csv_import.error_count).to eq(0)
      expect(csv_import.started_at).to be_present
      expect(csv_import.finished_at).to be_present
    end

    it "logs row-level errors to result and csv_import.error_log" do
      importer = described_class.new(source: csv_with([ dividend_row ]), default_broker: nil, csv_import: csv_import)
      importer.call

      csv_import.reload
      expect(csv_import.error_count).to eq(1)
      expect(csv_import.error_log).to include("default_broker is required")
    end

    it "marks csv_import as failed when a fatal error is raised before parsing" do
      bogus = double("source")
      allow(bogus).to receive(:read).and_raise(StandardError, "boom")

      importer = described_class.new(source: bogus, default_broker: "Parametric", csv_import: csv_import)

      expect { importer.call }.to raise_error(StandardError, "boom")
      csv_import.reload
      expect(csv_import.status).to eq("failed")
      expect(csv_import.error_log).to match(/Fatal: StandardError: boom/)
    end

    it "strips junk markers from security name on import" do
      row = dividend_row(ticker: "FOO", cusip: "999999999")
      row = row.sub("MARRIOTT INTERNATIONAL -CL A @ 0.67 PER SHARE", "ACME CORP CORPORATE ACTION ID 123")

      described_class.new(source: csv_with([ row ]), default_broker: "Parametric", csv_import: csv_import).call

      expect(Security.find_by(ticker: "FOO").name).to eq("ACME CORP")
    end

    it "upgrades an existing security's junk name when a clean description appears" do
      sec = create(:security, ticker: "MAR", cusip: "571903202", name: "")

      described_class.new(source: csv_with([ dividend_row ]), default_broker: "Parametric", csv_import: csv_import).call

      expect(sec.reload.name).to eq("MARRIOTT INTERNATIONAL -CL A")
    end

    it "strips a UTF-8 BOM at the start of the file" do
      bom = "\xEF\xBB\xBF".b
      raw = bom + header + "\n" + dividend_row + "\n"
      io = StringIO.new(raw)

      result = described_class.new(source: io, default_broker: "Parametric", csv_import: csv_import).call

      expect(result.imported).to eq(1)
    end
  end
end
