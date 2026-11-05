require "rails_helper"

RSpec.describe TransactionType, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:investment_transactions).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:transaction_type) }

    it { is_expected.to validate_presence_of(:code) }
    it { is_expected.to validate_uniqueness_of(:code) }
  end
end
