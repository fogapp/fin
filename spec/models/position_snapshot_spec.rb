require "rails_helper"

RSpec.describe PositionSnapshot, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:security) }
  end

  describe "validations" do
    subject { build(:position_snapshot) }

    it { is_expected.to validate_presence_of(:as_of_date) }
    it { is_expected.to validate_presence_of(:source_row_hash) }
    it { is_expected.to validate_uniqueness_of(:source_row_hash) }
  end

  describe "scopes" do
    let(:account)  { create(:account) }
    let(:security) { create(:security) }

    describe ".chronological" do
      it "orders by as_of_date ascending" do
        b = create(:position_snapshot, account: account, security: security, as_of_date: Date.new(2025, 2, 1))
        a = create(:position_snapshot, account: account, security: create(:security), as_of_date: Date.new(2025, 1, 1))

        expect(PositionSnapshot.chronological).to eq([ a, b ])
      end
    end
  end
end
