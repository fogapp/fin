require "rails_helper"
require "stringio"

RSpec.describe Importers::CheckingCsv do
  let(:csv_import) { create(:csv_import) }
  let(:account)    { create(:account) }

  def header
    "Trade Date,Post Date,Description,Type,Amount USD,Balance,Tran Code,Tran Code Description"
  end

  def csv_with(rows)
    StringIO.new(([ header ] + rows).join("\n"))
  end

  def checking_row(date: "01/15/2025", desc: "ACH WITHDRAWAL", type: "Debit",
                   amount: "-150.00", balance: "1000.00", tran_code: "001", tran_desc: "ACH OUT")
    [ date, date, desc, type, amount, balance, tran_code, tran_desc ].join(",")
  end

  describe "#call" do
    it "imports a checking transaction as a bank CashTransaction" do
      importer = described_class.new(source: csv_with([ checking_row ]), csv_import: csv_import, account: account)

      result = importer.call

      expect(result.imported).to eq(1)
      expect(result.skipped).to eq(0)
      expect(result.errors).to be_empty

      txn = CashTransaction.first
      expect(txn.source).to eq("bank")
      expect(txn.transaction_date).to eq(Date.new(2025, 1, 15))
      expect(txn.description).to eq("ACH WITHDRAWAL")
      expect(txn.amount).to eq(BigDecimal("-150.00"))
      expect(txn.balance).to eq(BigDecimal("1000.00"))
      expect(txn.tran_code).to eq("001")
      expect(txn.account).to eq(account)
    end

    it "is idempotent on duplicate rows" do
      described_class.new(source: csv_with([ checking_row ]), csv_import: csv_import, account: account).call
      result = described_class.new(source: csv_with([ checking_row ]), csv_import: create(:csv_import), account: account).call

      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(1)
      expect(CashTransaction.count).to eq(1)
    end

    it "matches a merchant via RuleMatcher" do
      m = create(:merchant, name: "ACH")
      create(:merchant_rule, merchant: m, pattern: "ACH WITHDRAWAL")

      described_class.new(source: csv_with([ checking_row ]), csv_import: csv_import, account: account).call

      txn = CashTransaction.first
      expect(txn.merchant).to eq(m)
    end

    it "skips fully blank rows" do
      blank = ",,,,,,,"
      importer = described_class.new(source: csv_with([ blank, checking_row ]), csv_import: csv_import, account: account)

      expect(importer.call.imported).to eq(1)
    end

    it "updates csv_import to completed with counts" do
      described_class.new(source: csv_with([ checking_row ]), csv_import: csv_import, account: account).call

      csv_import.reload
      expect(csv_import.status).to eq("completed")
      expect(csv_import.imported_count).to eq(1)
    end
  end
end
