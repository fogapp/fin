require "rails_helper"

RSpec.describe MarketPrice, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:security) }
  end

  describe "validations" do
    subject { build(:market_price) }

    it { is_expected.to validate_presence_of(:date) }

    it "scopes date uniqueness to security" do
      security = create(:security)
      create(:market_price, security: security, date: Date.new(2025, 1, 1))

      duplicate = build(:market_price, security: security, date: Date.new(2025, 1, 1))
      expect(duplicate).not_to be_valid
    end

    it "allows same date for different securities" do
      d = Date.new(2025, 1, 1)
      create(:market_price, security: create(:security), date: d)
      other = build(:market_price, security: create(:security), date: d)

      expect(other).to be_valid
    end
  end

  describe "scopes" do
    describe ".chronological" do
      it "orders by date ascending" do
        s = create(:security)
        feb = create(:market_price, security: s, date: Date.new(2025, 2, 1))
        jan = create(:market_price, security: s, date: Date.new(2025, 1, 1))
        mar = create(:market_price, security: s, date: Date.new(2025, 3, 1))

        expect(MarketPrice.chronological).to eq([ jan, feb, mar ])
      end
    end
  end
end
