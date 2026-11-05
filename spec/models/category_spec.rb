require "rails_helper"

RSpec.describe Category, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:cash_transactions).dependent(:nullify) }
    it { is_expected.to have_many(:merchants).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:category) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:household_id, :parent_id) }
  end
end
