require "rails_helper"

RSpec.describe Workflows::Actions::AssignAccount do
  let(:account) { create(:account) }
  let(:txn)     { create(:cash_transaction, :credit_card, :sale) }

  def action(account_id)
    described_class.new(account_id: account_id)
  end

  it "assigns the account and returns :applied" do
    result = action(account.id).execute(txn)
    expect(result[:status]).to eq(:applied)
    expect(result[:changes][:account_id][1]).to eq(account.id)
    expect(txn.reload.account_id).to eq(account.id)
  end

  it "skips when account is already assigned" do
    txn.update_columns(account_id: account.id)
    result = action(account.id).execute(txn)
    expect(result[:status]).to eq(:skipped)
  end

  it "does not persist in dry_run mode" do
    original_account_id = txn.account_id
    result = action(account.id).execute(txn, dry_run: true)
    expect(result[:status]).to eq(:applied)
    expect(txn.reload.account_id).to eq(original_account_id)
  end

  it "bumps the household data version so cached endpoints rotate" do
    txn && account
    expect(Households::DataVersion).to receive(:bump_coalesced!).with(txn.household_id)
    action(account.id).execute(txn)
  end

  it "does not bump the data version in dry_run mode" do
    txn && account
    expect(Households::DataVersion).not_to receive(:bump_coalesced!)
    action(account.id).execute(txn, dry_run: true)
  end
end
