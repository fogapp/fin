require "rails_helper"

RSpec.describe EstimatedTaxPayment, type: :model do
  it "is valid with the factory defaults" do
    expect(build(:estimated_tax_payment)).to be_valid
  end

  it { is_expected.to validate_presence_of(:paid_on) }
  it { is_expected.to validate_inclusion_of(:jurisdiction).in_array(%w[federal state]) }

  it "rejects non-positive amounts" do
    expect(build(:estimated_tax_payment, amount: 0)).not_to be_valid
    expect(build(:estimated_tax_payment, amount: -5)).not_to be_valid
  end

  it "rejects out-of-range tax years" do
    expect(build(:estimated_tax_payment, tax_year: 1999)).not_to be_valid
    expect(build(:estimated_tax_payment, tax_year: 2101)).not_to be_valid
  end

  it "fills household from Current on create" do
    expect(create(:estimated_tax_payment).household).to eq(Current.household)
  end
end
