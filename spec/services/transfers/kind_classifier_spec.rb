require "rails_helper"

RSpec.describe Transfers::KindClassifier do
  let(:checking) { create(:account, account_type: "Checking", name: "Family Checking") }
  let(:mortgage) { create(:account, account_type: "Mortgage", name: "Mortgage") }

  it "classifies a pair whose inflow lands in a liability account as a loan payment, counted in spend" do
    debit  = create(:cash_transaction, :bank, account: checking, amount: -8078.12,
                    description: "JPMORGAN CHASE CHASE ACH", raw_category: "TRANSFER_OUT_ACCOUNT_TRANSFER")
    credit = create(:cash_transaction, :bank, account: mortgage, amount: 8078.12,
                    description: "PAYMENT", raw_category: "TRANSFER_IN_ACCOUNT_TRANSFER")

    classification = described_class.new(from: debit, to: credit).classify

    expect(classification.kind).to eq(Transfer::Kind::LoanPayment)
    expect(classification.include_in_spend).to be(true)
  end

  it "classifies a one-sided payment to a liability counterparty as a loan payment" do
    debit = create(:cash_transaction, :bank, account: checking, amount: -2232.72,
                   description: "Online Payment 123 To Auto Loan 1111")
    loan  = create(:account, account_type: "Auto Loan", name: "Land Rover", kind: "external")

    classification = described_class.new(from: debit, to: nil, counterparty: loan).classify

    expect(classification.kind).to eq(Transfer::Kind::LoanPayment)
  end

  it "matches liability types case-insensitively and leaves other account types alone" do
    savings = create(:account, account_type: "Savings", name: "Savings")
    debit   = create(:cash_transaction, :bank, account: checking, amount: -100.00)
    credit  = create(:cash_transaction, :bank, account: savings, amount: 100.00)
    expect(described_class.new(from: debit, to: credit).classify.kind).to eq(Transfer::Kind::Transfer)

    heloc  = create(:account, account_type: "line of credit", name: "HELOC")
    credit = create(:cash_transaction, :bank, account: heloc, amount: 100.00)
    expect(described_class.new(from: debit, to: credit).classify.kind).to eq(Transfer::Kind::LoanPayment)
  end
end
