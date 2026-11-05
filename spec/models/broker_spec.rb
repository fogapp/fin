require "rails_helper"

RSpec.describe Broker, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:accounts).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:broker) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:household_id).case_insensitive }
  end

  describe "dependent: :restrict_with_error" do
    it "blocks deletion when accounts exist" do
      broker = create(:broker)
      create(:account, broker: broker)

      expect(broker.destroy).to be(false)
      expect(broker.errors[:base]).to be_present
    end
  end
end
