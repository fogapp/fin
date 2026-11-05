require "rails_helper"

RSpec.describe Workflows::Actions::AddTag do
  let(:tag) { create(:tag) }
  let(:txn) { create(:cash_transaction, :credit_card, :sale) }

  def action(tag_id)
    described_class.new(tag_id: tag_id)
  end

  it "adds the tag and returns :applied" do
    result = action(tag.id).execute(txn)
    expect(result[:status]).to eq(:applied)
    expect(result[:changes][:tag_name]).to eq(tag.name)
    expect(txn.tags.reload).to include(tag)
  end

  it "skips when the tag is already applied" do
    txn.tags << tag
    result = action(tag.id).execute(txn)
    expect(result[:status]).to eq(:skipped)
    expect(txn.tags.count).to eq(1)
  end

  it "returns :error when tag does not exist" do
    result = action("00000000-0000-0000-0000-000000000000").execute(txn)
    expect(result[:status]).to eq(:error)
    expect(result[:error]).to match(/not found/)
  end

  it "does not persist in dry_run mode" do
    result = action(tag.id).execute(txn, dry_run: true)
    expect(result[:status]).to eq(:applied)
    expect(txn.tags.reload).to be_empty
  end
end
