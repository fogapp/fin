require "rails_helper"

RSpec.describe Importers::Preview do
  let(:account) { create(:account, account_type: "Checking") }

  def preview(csv, account: self.account) = described_class.new(csv: csv, account: account).call

  it "is ready for a clean spreadsheet, with a parsed sample" do
    result = preview("Date,Description,Amount\n01/15/2026,Coffee,-4.50\n46053,Rent,(1500)\n")

    expect(result).to include(format: "spreadsheet", ready: true, row_count: 2, imports_as: "bank", invalid_row_count: 0, problems: [])
    expect(result[:sample]).to eq([
      { row: 2, date: "2026-01-15", description: "Coffee", amount: -4.5, type: "Sale" },
      { row: 3, date: "2026-01-31", description: "Rent", amount: -1500.0, type: "Sale" }
    ])
    expect(result[:columns].find { |c| c[:name] == "Amount" }).to eq({ name: "Amount", required: true, found: "Amount" })
    expect(CashTransaction.count).to eq(0)
  end

  it "points at rows that won't import, by the sheet's row number" do
    result = preview("Date,Description,Amount\n01/15/2026,Coffee,-4.50\n\n13/45/2026,,-3\n")

    expect(result).to include(ready: true, row_count: 2, invalid_row_count: 1)
    expect(result[:problems]).to eq([
      { row: 4, message: "“13/45/2026” in Date isn't a date Fin reads (use 01/31/2026 or 2026-01-31); Description is blank" }
    ])
  end

  it "explains a header row that matches nothing, with renames" do
    result = preview("When,Payee,Amt\n01/15/2026,Coffee,-4.50\n")

    expect(result).to include(format: "unknown", ready: false)
    expect(result[:suggestions]).to eq([
      { from: "When", to: "Date" }, { from: "Payee", to: "Description" }, { from: "Amt", to: "Amount" }
    ])
    expect(result[:problems].first[:message]).to include("needs Date, Description, Amount")
    expect(result[:columns].map { |c| c[:found] }.compact).to be_empty
  end

  it "isn't ready without an account to import into" do
    result = preview("Date,Description,Amount\n01/15/2026,Coffee,-4.50\n", account: nil)

    expect(result[:ready]).to be(false)
    expect(result[:problems].first[:message]).to include("Pick the account")
  end

  it "isn't ready when every row is bad, or there are none" do
    expect(preview("Date,Description,Amount\nsoon,Coffee,-4\n")[:ready]).to be(false)
    expect(preview("Date,Description,Amount\n")[:problems].first[:message]).to include("no rows")
  end

  it "recognises a bank export by its own headers" do
    result = preview("Transaction Date,Post Date,Description,Category,Type,Amount,Memo\n01/15/2026,01/16/2026,Coffee,Food,Sale,-4.50,\n")

    expect(result).to include(format: "credit_card", format_label: "Credit card export", ready: true)
  end

  it "reports a file that isn't CSV" do
    result = preview("Date,Description\n\"unterminated,1\n")

    expect(result[:ready]).to be(false)
    expect(result[:problems].first[:message]).to include("couldn't read this as CSV")
  end
end
