require "rails_helper"

RSpec.describe Importers::SpreadsheetFormat do
  describe ".missing" do
    it "is empty for the canonical headers, in any case and spacing" do
      expect(described_class.missing([ " date ", "DESCRIPTION", "Amount" ])).to be_empty
    end

    it "accepts Debit or Credit in place of Amount" do
      expect(described_class.missing(%w[Date Description Debit])).to be_empty
      expect(described_class.missing(%w[Date Description Credit])).to be_empty
    end

    it "names the required columns that aren't there" do
      expect(described_class.missing(%w[Date Payee])).to eq(%w[Description Amount])
    end
  end

  describe ".suggestions" do
    it "offers renames for headers that look like a missing column" do
      expect(described_class.suggestions([ "Transaction Date", "Payee", "Amt" ])).to eq([
        { from: "Transaction Date", to: "Date" },
        { from: "Payee", to: "Description" },
        { from: "Amt", to: "Amount" }
      ])
    end

    it "doesn't suggest a header already used as another column" do
      # Memo is a column of its own, so it's never offered as Description.
      expect(described_class.suggestions(%w[Date Memo Amount])).to be_empty
      expect(described_class.suggestions([ "Date", "Payee", "Merchant", "Amount" ])).to eq([ { from: "Payee", to: "Description" } ])
    end
  end

  describe ".parse_date" do
    it "reads US, short-year and ISO dates" do
      expect(described_class.parse_date("01/31/2026")).to eq(Date.new(2026, 1, 31))
      expect(described_class.parse_date("1/5/26")).to eq(Date.new(2026, 1, 5))
      expect(described_class.parse_date("2026-01-31")).to eq(Date.new(2026, 1, 31))
      expect(described_class.parse_date("2026-01-31T00:00:00")).to eq(Date.new(2026, 1, 31))
    end

    it "reads a spreadsheet serial number, as Office hands back a date cell" do
      expect(described_class.parse_date("46053")).to eq(Date.new(2026, 1, 31))
      expect(described_class.parse_date("46053.5")).to eq(Date.new(2026, 1, 31))
    end

    it "rejects day-first, out-of-range and implausible values" do
      expect(described_class.parse_date("31/01/2026")).to be_nil
      expect(described_class.parse_date("Jan 31")).to be_nil
      expect(described_class.parse_date("54.20")).to be_nil
      expect(described_class.parse_date("")).to be_nil
    end
  end

  describe ".parse_amount" do
    it "reads currency formatting and accounting negatives" do
      expect(described_class.parse_amount("-1,204.50")).to eq(BigDecimal("-1204.50"))
      expect(described_class.parse_amount("$54.20")).to eq(BigDecimal("54.20"))
      expect(described_class.parse_amount("-$54.20")).to eq(BigDecimal("-54.20"))
      expect(described_class.parse_amount("(54.20)")).to eq(BigDecimal("-54.20"))
      expect(described_class.parse_amount("12")).to eq(BigDecimal("12"))
    end

    it "rejects text" do
      expect(described_class.parse_amount("about 12")).to be_nil
      expect(described_class.parse_amount("")).to be_nil
    end
  end

  describe ".amount" do
    it "nets Debit and Credit, money out negative" do
      expect(described_class.amount({ "Debit" => "40", "Credit" => "" })).to eq([ BigDecimal("-40"), nil ])
      expect(described_class.amount({ "Debit" => "", "Credit" => "$1,000" })).to eq([ BigDecimal("1000"), nil ])
    end

    it "explains a blank or unreadable amount" do
      expect(described_class.amount({ "Amount" => "" })).to eq([ nil, "Amount is blank" ])
      expect(described_class.amount({ "Amount" => "n/a" })).to eq([ nil, "“n/a” in Amount isn't a number" ])
      expect(described_class.amount({ "Debit" => "", "Credit" => "" })).to eq([ nil, "Debit and Credit are both blank" ])
    end
  end

  describe ".source_for" do
    it "follows the account's existing rows" do
      account = create(:account, account_type: "Checking")
      create(:cash_transaction, account: account, source: "credit_card")
      expect(described_class.source_for(account)).to eq("credit_card")
    end

    it "treats a new credit card account as card activity, anything else as bank" do
      expect(described_class.source_for(create(:account, account_type: "Credit Card"))).to eq("credit_card")
      expect(described_class.source_for(create(:account, account_type: "Checking"))).to eq("bank")
    end
  end

  describe ".inferred_type" do
    it "mirrors Plaid ingest: out is a Sale, in is a Return, a card payment signature is a Payment" do
      expect(described_class.inferred_type(BigDecimal("-5"), "Coffee", "bank")).to eq("Sale")
      expect(described_class.inferred_type(BigDecimal("5"), "Refund", "credit_card")).to eq("Return")
      expect(described_class.inferred_type(BigDecimal("500"), "AUTOPAY PAYMENT - THANK YOU", "credit_card")).to eq("Payment")
    end
  end
end
