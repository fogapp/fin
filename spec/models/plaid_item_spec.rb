require "rails_helper"

RSpec.describe PlaidItem do
  describe "associations" do
    it { is_expected.to have_many(:plaid_accounts).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:plaid_item) }

    it { is_expected.to validate_presence_of(:item_id) }
    it { is_expected.to validate_presence_of(:access_token) }
    it { is_expected.to validate_uniqueness_of(:item_id) }
  end

  describe "enums" do
    it "defaults to active status" do
      item = build(:plaid_item)
      expect(item.status).to eq("active")
    end

    it "accepts error status" do
      item = build(:plaid_item, status: "error")
      expect(item).to be_valid
    end
  end

  describe "#display_name" do
    it "returns the institution name when present" do
      item = build(:plaid_item, institution_name: "Chase")
      expect(item.display_name).to eq("Chase")
    end

    it "falls back to item_id when institution_name is blank" do
      item = build(:plaid_item, institution_name: nil, item_id: "item-xyz")
      expect(item.display_name).to eq("item-xyz")
    end
  end
end
