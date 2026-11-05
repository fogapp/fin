require "rails_helper"

RSpec.describe Workflows::Actions::AssignMerchant do
  let(:merchant) { create(:merchant) }
  let(:txn)      { create(:cash_transaction, :credit_card, :sale) }

  def action(merchant_id)
    described_class.new(merchant_id: merchant_id)
  end

  it "assigns the merchant and returns :applied" do
    result = action(merchant.id).execute(txn)
    expect(result[:status]).to eq(:applied)
    expect(result[:changes][:merchant_id]).to eq([ nil, merchant.id ])
    expect(txn.reload.merchant_id).to eq(merchant.id)
  end

  it "skips when merchant is already assigned" do
    txn.update_columns(merchant_id: merchant.id)
    result = action(merchant.id).execute(txn)
    expect(result[:status]).to eq(:skipped)
    expect(txn.reload.merchant_id).to eq(merchant.id)
  end

  it "does not persist in dry_run mode" do
    result = action(merchant.id).execute(txn, dry_run: true)
    expect(result[:status]).to eq(:applied)
    expect(txn.reload.merchant_id).to be_nil
  end

  it "bumps the household data version so cached endpoints rotate" do
    txn && merchant
    expect(Households::DataVersion).to receive(:bump_coalesced!).with(txn.household_id)
    action(merchant.id).execute(txn)
  end

  it "does not bump the data version in dry_run mode" do
    txn && merchant
    expect(Households::DataVersion).not_to receive(:bump_coalesced!)
    action(merchant.id).execute(txn, dry_run: true)
  end
end
