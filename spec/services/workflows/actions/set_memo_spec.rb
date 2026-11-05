require "rails_helper"

RSpec.describe Workflows::Actions::SetMemo do
  let(:txn) { create(:cash_transaction, :credit_card, :sale, memo: nil) }

  def action(value)
    described_class.new(value: value.to_s)
  end

  it "sets the memo and returns :applied" do
    result = action("review this").execute(txn)
    expect(result[:status]).to eq(:applied)
    expect(result[:changes][:memo]).to eq([ nil, "review this" ])
    expect(txn.reload.memo).to eq("review this")
  end

  it "skips when memo is already the same value" do
    txn.update_columns(memo: "review this")
    result = action("review this").execute(txn)
    expect(result[:status]).to eq(:skipped)
  end

  it "does not persist in dry_run mode" do
    result = action("review this").execute(txn, dry_run: true)
    expect(result[:status]).to eq(:applied)
    expect(txn.reload.memo).to be_nil
  end

  it "bumps the household data version so cached endpoints rotate" do
    txn
    expect(Households::DataVersion).to receive(:bump_coalesced!).with(txn.household_id)
    action("review this").execute(txn)
  end

  it "does not bump the data version in dry_run mode" do
    txn
    expect(Households::DataVersion).not_to receive(:bump_coalesced!)
    action("review this").execute(txn, dry_run: true)
  end
end
