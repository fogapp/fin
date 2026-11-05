require "rails_helper"

RSpec.describe TaxAdjustment, type: :model do
  it "is valid with the factory defaults" do
    expect(build(:tax_adjustment)).to be_valid
  end

  it { is_expected.to validate_inclusion_of(:kind).in_array(TaxAdjustment::Kind.values.map(&:serialize)) }
  it { is_expected.to validate_inclusion_of(:jurisdiction).in_array(Tax::Jurisdiction.values.map(&:serialize)) }
  it { is_expected.to validate_presence_of(:label) }

  it "allows negative amounts (reductions are legitimate line items)" do
    expect(build(:tax_adjustment, amount: -2_500)).to be_valid
  end

  it "accepts a bucket only on contribution adjustments" do
    expect(build(:tax_adjustment, kind: "contribution", bucket: "401k")).to be_valid
    expect(build(:tax_adjustment, kind: "contribution", bucket: nil)).to be_valid
    expect(build(:tax_adjustment, kind: "income", bucket: "401k")).not_to be_valid
    expect(build(:tax_adjustment, kind: "contribution", bucket: "sep_ira")).not_to be_valid
  end
end
