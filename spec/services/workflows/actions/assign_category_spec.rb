require "rails_helper"

RSpec.describe Workflows::Actions::AssignCategory do
  let(:category) { create(:category) }
  let(:txn)      { create(:cash_transaction, :credit_card, :sale) }

  def action(category_id)
    described_class.new(category_id: category_id)
  end

  it "assigns the category and returns :applied" do
    result = action(category.id).execute(txn)
    expect(result[:status]).to eq(:applied)
    expect(result[:changes][:category_id]).to eq([ nil, category.id ])
    expect(txn.reload.category_id).to eq(category.id)
  end

  it "skips when category is already assigned" do
    txn.update_columns(category_id: category.id)
    result = action(category.id).execute(txn)
    expect(result[:status]).to eq(:skipped)
  end

  it "does not persist in dry_run mode" do
    result = action(category.id).execute(txn, dry_run: true)
    expect(result[:status]).to eq(:applied)
    expect(txn.reload.category_id).to be_nil
  end

  it "bumps the household data version so cached endpoints rotate" do
    txn && category
    expect(Households::DataVersion).to receive(:bump_coalesced!).with(txn.household_id)
    action(category.id).execute(txn)
  end

  it "does not bump the data version in dry_run mode" do
    txn && category
    expect(Households::DataVersion).not_to receive(:bump_coalesced!)
    action(category.id).execute(txn, dry_run: true)
  end
end
