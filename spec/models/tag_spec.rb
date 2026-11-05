require "rails_helper"

RSpec.describe Tag, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:cash_transaction_tags).dependent(:destroy) }
    it { is_expected.to have_many(:cash_transactions).through(:cash_transaction_tags) }
  end

  describe "validations" do
    subject { build(:tag) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:household_id).case_insensitive }
  end

  describe "name normalization" do
    it "strips whitespace before saving" do
      tag = create(:tag, name: "  groceries  ")
      expect(tag.name).to eq("groceries")
    end
  end
end
