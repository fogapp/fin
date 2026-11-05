require "rails_helper"

RSpec.describe EquityFmvEntry, type: :model do
  let(:company) { create(:equity_company) }

  it "rejects a second entry for the same company and date" do
    create(:equity_fmv_entry, equity_company: company, effective_date: Date.new(2026, 1, 15))
    dup = build(:equity_fmv_entry, equity_company: company, effective_date: Date.new(2026, 1, 15))

    expect(dup).not_to be_valid
    expect(dup.errors[:effective_date]).to be_present
  end

  it "allows the same date on a different company" do
    create(:equity_fmv_entry, equity_company: company, effective_date: Date.new(2026, 1, 15))
    other = build(:equity_fmv_entry, equity_company: create(:equity_company),
                  effective_date: Date.new(2026, 1, 15))
    expect(other).to be_valid
  end

  it "validates source and positive price" do
    expect(build(:equity_fmv_entry, source: "guess")).not_to be_valid
    expect(build(:equity_fmv_entry, price_per_share: 0)).not_to be_valid
  end

  it "flags entries older than 12 months as stale" do
    expect(build(:equity_fmv_entry, effective_date: 13.months.ago.to_date)).to be_stale
    expect(build(:equity_fmv_entry, effective_date: 11.months.ago.to_date)).not_to be_stale
  end
end
