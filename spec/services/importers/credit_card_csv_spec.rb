require "rails_helper"
require "stringio"

RSpec.describe Importers::CreditCardCsv do
  let(:csv_import) { create(:csv_import) }
  let(:account)    { create(:account) }

  def header
    "Transaction Date,Post Date,Description,Category,Type,Amount,Memo"
  end

  def csv_with(rows)
    StringIO.new(([ header ] + rows).join("\n"))
  end

  def cc_row(date: "01/15/2025", desc: "STARBUCKS #1234", category: "Coffee Shops",
             type: "Sale", amount: "-5.75", memo: "")
    [ date, date, desc, category, type, amount, memo ].join(",")
  end

  describe "#call" do
    it "imports two legitimately identical rows in one statement" do
      # Same coffee, same day, same amount — the old content-only hash
      # silently skipped the second row.
      importer = described_class.new(source: csv_with([ cc_row, cc_row ]),
                                     csv_import: csv_import, account: account)

      result = importer.call

      expect(result.imported).to eq(2)
      expect(result.skipped).to eq(0)
    end

    it "still skips rows already imported under the legacy content hash" do
      legacy_hash = Digest::SHA256.hexdigest(
        CSV.parse_line(cc_row, headers: CSV.parse_line(header)).to_h.to_a.sort.to_s
      )
      create(:cash_transaction, :credit_card, account: account, source_row_hash: legacy_hash)

      importer = described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account)
      result = importer.call

      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(1)
    end

    it "imports the same data into a different account instead of skipping" do
      other_account = create(:account)
      described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account).call

      result = described_class.new(source: csv_with([ cc_row ]),
                                   csv_import: create(:csv_import), account: other_account).call

      expect(result.imported).to eq(1)
      expect(result.skipped).to eq(0)
    end

    it "is idempotent when the same file is imported twice" do
      described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account).call
      result = described_class.new(source: csv_with([ cc_row ]),
                                   csv_import: create(:csv_import), account: account).call

      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(1)
    end

    it "imports a credit card transaction as a credit_card CashTransaction" do
      importer = described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account)

      result = importer.call

      expect(result.imported).to eq(1)
      expect(result.skipped).to eq(0)
      expect(result.errors).to be_empty

      txn = CashTransaction.first
      expect(txn.source).to eq("credit_card")
      expect(txn.transaction_date).to eq(Date.new(2025, 1, 15))
      expect(txn.description).to eq("STARBUCKS #1234")
      expect(txn.amount).to eq(BigDecimal("-5.75"))
      expect(txn.transaction_type).to eq("Sale")
      expect(txn.account).to eq(account)
      expect(txn.raw_category).to eq("Coffee Shops")
    end

    it "is idempotent on identical rows" do
      described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account).call
      result = described_class.new(source: csv_with([ cc_row ]), csv_import: create(:csv_import), account: account).call

      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(1)
      expect(CashTransaction.count).to eq(1)
    end

    it "matches a merchant via RuleMatcher" do
      sbux = create(:merchant, name: "Starbucks")
      create(:merchant_rule, merchant: sbux, pattern: "STARBUCKS")

      described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account).call

      txn = CashTransaction.first
      expect(txn.merchant).to eq(sbux)
    end

    it "uses the rule's category override when available" do
      coffee = create(:category, name: "Coffee")
      sbux = create(:merchant, name: "Starbucks", category: create(:category, name: "Default"))
      create(:merchant_rule, merchant: sbux, pattern: "STARBUCKS", category: coffee)

      described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account).call

      txn = CashTransaction.first
      expect(txn.category).to eq(coffee)
    end

    it "falls back to category by raw_category name when no rule matches" do
      create(:category, name: "Coffee Shops")

      described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account).call

      txn = CashTransaction.first
      expect(txn.merchant).to be_nil
      expect(txn.category.name).to eq("Coffee Shops")
    end

    it "skips fully blank rows" do
      blank = ",,,,,,"
      importer = described_class.new(source: csv_with([ blank, cc_row ]), csv_import: csv_import, account: account)

      result = importer.call
      expect(result.imported).to eq(1)
    end

    it "updates the csv_import record with completion details" do
      described_class.new(source: csv_with([ cc_row ]), csv_import: csv_import, account: account).call

      csv_import.reload
      expect(csv_import.status).to eq("completed")
      expect(csv_import.imported_count).to eq(1)
      expect(csv_import.error_count).to eq(0)
    end

    it "marks csv_import as failed on a fatal pre-parse error" do
      bogus = double("source")
      allow(bogus).to receive(:read).and_raise(StandardError, "io broke")

      expect {
        described_class.new(source: bogus, csv_import: csv_import, account: account).call
      }.to raise_error(StandardError, "io broke")

      csv_import.reload
      expect(csv_import.status).to eq("failed")
      expect(csv_import.error_log).to match(/Fatal/)
    end
  end
end
