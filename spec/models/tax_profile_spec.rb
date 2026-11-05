require "rails_helper"

RSpec.describe TaxProfile, type: :model do
  it "is valid with factory defaults" do
    expect(build(:tax_profile)).to be_valid
  end

  it "enforces one profile per (household, tax_year)" do
    create(:tax_profile, tax_year: 2026)
    expect(build(:tax_profile, tax_year: 2026)).not_to be_valid
    expect(build(:tax_profile, tax_year: 2027)).to be_valid
  end

  it "allows the same tax_year in a different household" do
    create(:tax_profile, tax_year: 2026)
    other = create(:household)
    profile = Current.set(household: other) { build(:tax_profile, tax_year: 2026, household: other) }
    expect(profile).to be_valid
  end

  it "only accepts single and mfj filing statuses (v1)" do
    expect(build(:tax_profile, filing_status: "mfj")).to be_valid
    expect(build(:tax_profile, filing_status: "hoh")).not_to be_valid
  end

  it "rejects negative amounts and allows nil prior-year facts" do
    expect(build(:tax_profile, projected_wages: -1)).not_to be_valid
    expect(build(:tax_profile, prior_year_total_tax: nil, prior_year_agi: nil)).to be_valid
    expect(build(:tax_profile, prior_year_total_tax: -5)).not_to be_valid
  end

  describe "state" do
    it "accepts US state codes only" do
      expect(build(:tax_profile, state: "TX")).to be_valid
      expect(build(:tax_profile, state: "ZZ")).not_to be_valid
    end

    it "requires a non-negative projected state tax for states Fin doesn't model" do
      expect(build(:tax_profile, state: "NY")).not_to be_valid
      expect(build(:tax_profile, state: "NY", projected_state_tax: 10_000)).to be_valid
      expect(build(:tax_profile, state: "NY", projected_state_tax: -1)).not_to be_valid
    end

    it "derives where the state tax comes from" do
      expect(build(:tax_profile).state_tax_source).to eq(Tax::States::Source::Modeled)
      expect(build(:tax_profile, projected_state_tax: 5_000).state_tax_source).to eq(Tax::States::Source::Entered)
      expect(build(:tax_profile, state: "WA").state_tax_source).to eq(Tax::States::Source::NoIncomeTax)
      expect(build(:tax_profile, state: "NY", projected_state_tax: 0).state_tax_source).to eq(Tax::States::Source::Entered)
    end
  end

  describe "#complete?" do
    it "requires positive projected wages" do
      expect(build(:tax_profile, projected_wages: 0)).not_to be_complete
      expect(build(:tax_profile, projected_wages: 1)).to be_complete
    end
  end

  it "is household-scoped" do
    profile = create(:tax_profile)
    other = create(:household)
    Current.set(household: other) do
      expect(TaxProfile.find_by(id: profile.id)).to be_nil
    end
  end
end
