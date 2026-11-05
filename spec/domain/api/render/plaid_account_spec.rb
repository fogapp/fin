require "rails_helper"

RSpec.describe Api::Render::PlaidAccount do
  def renderer = described_class.new(params: ActionController::Parameters.new)

  describe "#index" do
    it "returns all accounts ordered by name" do
      create(:plaid_account, name: "Savings")
      create(:plaid_account, name: "Checking")

      names = renderer.index.map { |a| a[:name] }
      expect(names).to eq([ "Checking", "Savings" ])
    end

    it "includes institution_name from the parent item" do
      item = create(:plaid_item, institution_name: "Chase")
      create(:plaid_account, plaid_item: item)

      result = renderer.index
      expect(result.first[:institution_name]).to eq("Chase")
    end
  end

  describe "#serialize" do
    it "includes all expected fields" do
      plaid_account = create(:plaid_account)
      result        = renderer.serialize(plaid_account)
      expect(result.keys).to match_array(%i[
        id name display_name mask account_type account_subtype
        linked account_id plaid_item_id institution_name
        balance_current balance_available balance_limit balance_currency balance_updated_at
      ])
    end

    it "reflects linked status" do
      account       = create(:account)
      plaid_account = create(:plaid_account, account: account)
      result        = renderer.serialize(plaid_account)
      expect(result[:linked]).to be true
      expect(result[:account_id]).to eq(account.id)
    end

    it "reflects unlinked status" do
      plaid_account = create(:plaid_account, account: nil)
      result        = renderer.serialize(plaid_account)
      expect(result[:linked]).to be false
      expect(result[:account_id]).to be_nil
    end
  end
end
