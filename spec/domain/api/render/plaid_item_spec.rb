require "rails_helper"

RSpec.describe Api::Render::PlaidItem do
  def renderer = described_class.new(params: ActionController::Parameters.new)

  describe "#index" do
    it "returns all items ordered by institution name" do
      create(:plaid_item, institution_name: "Wells Fargo")
      create(:plaid_item, institution_name: "Chase")

      names = renderer.index.map { |i| i[:institution_name] }
      expect(names).to eq([ "Chase", "Wells Fargo" ])
    end

    it "includes plaid_accounts for each item" do
      item = create(:plaid_item)
      create(:plaid_account, plaid_item: item)

      result = renderer.index
      expect(result.first[:plaid_accounts].length).to eq(1)
    end

    it "includes bank_count and credit_card_count per linked account" do
      account       = create(:account)
      plaid_account = create(:plaid_account, account: account)
      create(:cash_transaction, :bank, :debit, account: account)
      create(:cash_transaction, :credit_card, :sale, account: account)

      result = renderer.index
      acct   = result.first[:plaid_accounts].first
      expect(acct[:bank_count]).to eq(1)
      expect(acct[:credit_card_count]).to eq(1)
    end
  end

  describe "#serialize" do
    it "includes all expected top-level fields" do
      item   = create(:plaid_item)
      result = renderer.serialize(item)
      expect(result.keys).to match_array(%i[
        id institution_name institution_id status last_synced_at plaid_accounts
      ])
    end

    it "includes linked status for each account" do
      item    = create(:plaid_item)
      account = create(:account)
      create(:plaid_account, plaid_item: item, account: account)
      create(:plaid_account, plaid_item: item, account: nil)

      result  = renderer.serialize(item.reload)
      linked  = result[:plaid_accounts].map { |a| a[:linked] }
      expect(linked).to contain_exactly(true, false)
    end
  end
end
