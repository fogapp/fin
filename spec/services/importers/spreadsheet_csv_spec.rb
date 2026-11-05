require "rails_helper"
require "stringio"

RSpec.describe Importers::SpreadsheetCsv do
  let(:csv_import) { create(:csv_import) }
  let(:account)    { create(:account, account_type: "Checking") }

  def run(csv, account: self.account, import: csv_import)
    described_class.new(source: StringIO.new(csv), csv_import: import, account: account).call
  end

  it "imports Date/Description/Amount rows into the account" do
    result = run("Date,Description,Amount,Memo\n01/15/2026,Trader Joe's,-54.20,weekly shop\n2026-01-16,Paycheck,\"2,000.00\",\n")

    expect(result.imported).to eq(2)
    expect(result.errors).to be_empty
    shop = CashTransaction.find_by!(description: "Trader Joe's")
    expect(shop).to have_attributes(
      source: "bank", account: account, transaction_date: Date.new(2026, 1, 15),
      amount: BigDecimal("-54.20"), memo: "weekly shop", transaction_type: "Sale"
    )
    expect(CashTransaction.find_by!(description: "Paycheck").amount).to eq(BigDecimal("2000"))
  end

  it "reads Office serial-number dates and Debit/Credit columns" do
    run("date,description,debit,credit\n46053,Rent,1500,\n46054,Refund,,25\n")

    expect(CashTransaction.find_by!(description: "Rent")).to have_attributes(
      transaction_date: Date.new(2026, 1, 31), amount: BigDecimal("-1500")
    )
    expect(CashTransaction.find_by!(description: "Refund").amount).to eq(BigDecimal("25"))
  end

  it "imports as card activity into a credit card account, typing payments" do
    card = create(:account, account_type: "Credit Card")
    run("Date,Description,Amount\n01/02/2026,AUTOPAY PAYMENT - THANK YOU,500\n01/03/2026,Shell,-40\n", account: card)

    expect(CashTransaction.find_by!(description: "Shell")).to have_attributes(source: "credit_card", transaction_type: "Sale")
    expect(CashTransaction.find_by!(description: "AUTOPAY PAYMENT - THANK YOU").transaction_type).to eq("Payment")
  end

  it "uses the sheet's Type and Category when given" do
    groceries = create(:category, name: "Groceries")
    run("Date,Description,Amount,Type,Category\n01/02/2026,Market,-12,return,groceries\n")

    expect(CashTransaction.last).to have_attributes(transaction_type: "Return", category: groceries, raw_category: "groceries")
  end

  it "reports bad rows by what's wrong and imports the rest" do
    result = run("Date,Description,Amount\n31/01/2026,Coffee,-4\n01/02/2026,Tea,lots\n01/03/2026,Cake,-6\n")

    expect(result.imported).to eq(1)
    expect(result.errors.map { |e| e[:error] }).to contain_exactly(
      a_string_including("“31/01/2026” in Date isn't a date"),
      a_string_including("Tea: “lots” in Amount isn't a number")
    )
    expect(csv_import.reload.error_log).to include("isn't a number")
  end

  it "skips rows already imported when the sheet is imported again" do
    csv = "Date,Description,Amount\n01/15/2026,Coffee,-4\n01/15/2026,Coffee,-4\n"
    run(csv)
    result = run(csv, import: create(:csv_import))

    expect(result.skipped).to eq(2)
    expect(CashTransaction.count).to eq(2)
  end

  it "fails the import without an account" do
    expect { run("Date,Description,Amount\n01/15/2026,Coffee,-4\n", account: nil) }.to raise_error(ArgumentError, /needs an account/)
    expect(csv_import.reload.status).to eq("failed")
  end
end
