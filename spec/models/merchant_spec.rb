require "rails_helper"

RSpec.describe Merchant, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:merchant_rules).dependent(:destroy) }
    it { is_expected.to have_many(:cash_transactions).dependent(:nullify) }
    it { is_expected.to belong_to(:category).optional }
  end

  describe "validations" do
    subject { build(:merchant) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:household_id).case_insensitive }

    it "allows nil category on create" do
      m = build(:merchant, category: nil)
      expect(m).to be_valid
    end
  end

  describe "merchant_rules ordering" do
    it "orders rules by priority desc" do
      m = create(:merchant)
      low  = create(:merchant_rule, merchant: m, priority: 1)
      high = create(:merchant_rule, merchant: m, priority: 10)

      expect(m.merchant_rules.to_a).to eq([ high, low ])
    end
  end

  describe "dependent: :nullify on transactions" do
    it "clears merchant_id on cash_transactions when destroyed" do
      m = create(:merchant)
      txn = create(:cash_transaction, :credit_card, merchant: m)

      m.destroy

      expect(txn.reload.merchant_id).to be_nil
    end
  end

  describe "scopes" do
    it ".excluded returns excluded merchants" do
      active   = create(:merchant, name: "Active Merchant 2",   excluded: false)
      excluded = create(:merchant, name: "Excluded Merchant 2", excluded: true)

      result = Merchant.excluded
      expect(result).to include(excluded)
      expect(result).not_to include(active)
    end
  end
end
