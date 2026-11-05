require "rails_helper"
require "stringio"

RSpec.describe Importers::Dispatcher do
  let(:csv_import) { create(:csv_import) }

  def io(headers, body = "")
    StringIO.new(([ headers ] + Array(body)).join("\n"))
  end

  def dispatcher(headers)
    described_class.new(source: io(headers), csv_import: csv_import)
  end

  describe "#call" do
    it "detects checking format (Trade Date + Tran Code) and delegates" do
      headers = "Trade Date,Post Date,Tran Code,Tran Code Description,Description,Type,Amount USD,Balance"
      d = described_class.new(source: io(headers), csv_import: csv_import)

      expect(Importers::CheckingCsv).to receive(:new).and_return(double(call: :ok))
      d.call
      expect(csv_import.reload.kind).to eq("checking")
    end

    it "detects transactions format (Trade Date only) and delegates" do
      headers = "Trade Date,Account Name,Account Number,Account Type,Type,Description,Cusip,Ticker"
      d = described_class.new(source: io(headers), csv_import: csv_import)

      expect(Importers::BrokerCsv).to receive(:new).and_return(double(call: :ok))
      d.call
      expect(csv_import.reload.kind).to eq("transactions")
    end

    it "detects a full broker export as transactions even though it has Tran Code headers" do
      # Real broker exports carry Trade Date + Tran Code just like checking
      # exports; the securities columns (Quantity) are the discriminator.
      headers = "Trade Date,Post Date,Settlement Date,Account Name,Account Number,Account Type," \
                "Type,Tran Code,Tran Code Description,Description,Cusip,Ticker,Quantity," \
                "Price USD,Cost USD,Amount USD,Balance"
      d = described_class.new(source: io(headers), csv_import: csv_import)

      expect(Importers::BrokerCsv).to receive(:new).and_return(double(call: :ok))
      d.call
      expect(csv_import.reload.kind).to eq("transactions")
    end

    it "detects holdings format (Asset Class + Pricing Date) and delegates" do
      headers = "Ticker,CUSIP,Description,Asset Class,Pricing Date,Quantity"
      d = described_class.new(source: io(headers), csv_import: csv_import)

      expect(Importers::HoldingsCsv).to receive(:new).and_return(double(call: :ok))
      d.call
      expect(csv_import.reload.kind).to eq("holdings")
    end

    it "detects credit_card format (Transaction Date + Post Date) and delegates" do
      headers = "Transaction Date,Post Date,Description,Category,Type,Amount,Memo"
      d = described_class.new(source: io(headers), csv_import: csv_import)

      expect(Importers::CreditCardCsv).to receive(:new).and_return(double(call: :ok))
      d.call
      expect(csv_import.reload.kind).to eq("credit_card")
    end

    it "raises UnknownFormatError on unrecognized headers" do
      headers = "Foo,Bar,Baz,Quux"
      d = described_class.new(source: io(headers), csv_import: csv_import)

      expect { d.call }.to raise_error(Importers::Dispatcher::UnknownFormatError, /needs Date, Description, Amount/)
    end

    it "suggests renames when the headers are close to the spreadsheet layout" do
      d = described_class.new(source: io("Date,Payee,Amt"), csv_import: csv_import)

      expect { d.call }.to raise_error(
        Importers::Dispatcher::UnknownFormatError,
        /rename “Payee” to “Description”; rename “Amt” to “Amount”/
      )
    end

    it "detects the spreadsheet layout (Date, Description, Amount) and delegates" do
      account = create(:account)
      d = described_class.new(source: io("date,Description,AMOUNT,Memo"), csv_import: csv_import, target_account: account)

      expect(Importers::SpreadsheetCsv).to receive(:new).with(hash_including(account: account)).and_return(double(call: :ok))
      d.call
      expect(csv_import.reload.kind).to eq("spreadsheet")
    end

    it "strips a UTF-8 BOM before sniffing headers" do
      bom = "\xEF\xBB\xBF".b
      raw = bom + "Trade Date,Account Number,Type\n"
      io = StringIO.new(raw)
      d = described_class.new(source: io, csv_import: csv_import)

      expect(Importers::BrokerCsv).to receive(:new).and_return(double(call: :ok))
      d.call
    end

    it "rewinds the IO so the importer can re-read it" do
      headers = "Trade Date,Account Number,Type"
      io = StringIO.new(headers + "\n")
      d = described_class.new(source: io, csv_import: csv_import)
      allow(Importers::BrokerCsv).to receive(:new).and_return(double(call: :ok))

      d.call

      expect(io.pos).to eq(0)
    end
  end
end
