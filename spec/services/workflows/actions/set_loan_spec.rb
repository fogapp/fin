require "rails_helper"

RSpec.describe Workflows::Actions::SetLoan do
  let(:txn) { create(:cash_transaction, :credit_card, :sale, loan_id: nil) }
  let(:loan) { create(:loan) }

  def action(loan_id)
    described_class.new(loan_id: loan_id)
  end

  it "sets the loan and returns :applied" do
    result = action(loan.id).execute(txn)
    expect(result[:status]).to eq(:applied)
    expect(result[:changes][:loan_id]).to eq([ nil, loan.id ])
    expect(txn.reload.loan_id).to eq(loan.id)
  end

  it "skips when loan_id is already the same value" do
    txn.update_columns(loan_id: loan.id)
    result = action(loan.id).execute(txn)
    expect(result[:status]).to eq(:skipped)
  end

  it "does not persist in dry_run mode" do
    result = action(loan.id).execute(txn, dry_run: true)
    expect(result[:status]).to eq(:applied)
    expect(txn.reload.loan_id).to be_nil
  end

  it "bumps the household data version so cached endpoints rotate" do
    txn
    loan
    expect(Households::DataVersion).to receive(:bump_coalesced!).with(txn.household_id)
    action(loan.id).execute(txn)
  end

  it "does not bump the data version in dry_run mode" do
    txn
    loan
    expect(Households::DataVersion).not_to receive(:bump_coalesced!)
    action(loan.id).execute(txn, dry_run: true)
  end
end
