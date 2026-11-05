require "rails_helper"

RSpec.describe MerchantRule, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:merchant) }
    it { is_expected.to belong_to(:category).optional }
  end

  describe "validations" do
    subject { build(:merchant_rule) }

    it { is_expected.to validate_presence_of(:pattern) }

    describe "pattern_is_valid_regex" do
      it "accepts valid regex" do
        rule = build(:merchant_rule, pattern: 'STARBUCKS|SBUX')
        expect(rule).to be_valid
      end

      it "rejects an invalid regex" do
        rule = build(:merchant_rule, pattern: '[unbalanced')
        expect(rule).not_to be_valid
        expect(rule.errors[:pattern].first).to match(/not a valid regular expression/)
      end
    end
  end
end
