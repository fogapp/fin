require "rails_helper"

RSpec.describe TaxChecklistItem, type: :model do
  it "is valid with the factory defaults" do
    expect(build(:tax_checklist_item)).to be_valid
  end

  it { is_expected.to validate_inclusion_of(:kind).in_array(TaxChecklistItem::Kind.values.map(&:serialize)) }
  it { is_expected.to validate_inclusion_of(:status).in_array(TaxChecklistItem::Status.values.map(&:serialize)) }
  it { is_expected.to validate_presence_of(:source_label) }

  it "enforces uniqueness of source_label per (household, year, kind)" do
    create(:tax_checklist_item, tax_year: 2026, kind: "1098", source_label: "Home Loan")
    duplicate = build(:tax_checklist_item, tax_year: 2026, kind: "1098", source_label: "Home Loan")
    expect(duplicate).not_to be_valid

    expect(build(:tax_checklist_item, tax_year: 2025, kind: "1098", source_label: "Home Loan")).to be_valid
    expect(build(:tax_checklist_item, tax_year: 2026, kind: "other", source_label: "Home Loan")).to be_valid
  end

  it "allows the same label in another household" do
    create(:tax_checklist_item, tax_year: 2026, kind: "1098", source_label: "Home Loan")

    other = create(:household)
    Current.set(household: other) do
      expect(build(:tax_checklist_item, tax_year: 2026, kind: "1098", source_label: "Home Loan")).to be_valid
    end
  end
end
