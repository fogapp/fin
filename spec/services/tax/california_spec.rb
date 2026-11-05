require "rails_helper"

RSpec.describe Tax::California do
  def compute(**kwargs)
    described_class.new(tax_year: 2026, **kwargs).call
  end

  describe "worked example 3: single, $400k wages, $300k ISO spread" do
    subject(:result) { compute(filing_status: Tax::FilingStatus::Single, wages: 400_000, iso_spread: 300_000) }

    it "reproduces the design-doc numbers to the dollar" do
      expect(result[:taxable_income]).to eq(394_460.0) # 400,000 − 5,540 standard
      expect(result[:regular_tax]).to be_within(300).of(33_400)
      expect(result[:amti]).to eq(700_000.0) # taxable + standard addback + spread
      expect(result[:exemption]).to eq(4_701.0) # 92,749 − 0.25 × (700,000 − 347,808)
      expect(result[:tmt]).to be_within(50).of(48_671) # 7% × 695,299
      expect(result[:amt]).to be_within(300).of(15_300)
      expect(result[:amt]).to eq((result[:tmt] - result[:regular_tax]).round(2))
    end
  end

  describe "Behavioral Health Services Tax" do
    it "adds 1% only on taxable income over $1M" do
      below = compute(filing_status: Tax::FilingStatus::Single, wages: 1_005_540) # taxable exactly 1,000,000
      above = compute(filing_status: Tax::FilingStatus::Single, wages: 1_015_540) # taxable 1,010,000
      # Marginal across the threshold: 12.3% bracket + 1% BHST.
      expect(above[:regular_tax] - below[:regular_tax]).to be_within(0.01).of(10_000 * 0.133)

      just_below = compute(filing_status: Tax::FilingStatus::Single, wages: 995_540) # taxable 990,000
      expect(below[:regular_tax] - just_below[:regular_tax]).to be_within(0.01).of(10_000 * 0.123)
    end

    it "does not double the $1M threshold for MFJ" do
      below = compute(filing_status: Tax::FilingStatus::Mfj, wages: 1_011_080) # taxable 1,000,000
      above = compute(filing_status: Tax::FilingStatus::Mfj, wages: 1_021_080)
      expect(above[:regular_tax] - below[:regular_tax]).to be_within(0.01).of(10_000 * 0.113 + 10_000 * 0.01)
    end
  end

  describe "AMT" do
    it "has zero TMT when AMTI is under the exemption" do
      expect(compute(filing_status: Tax::FilingStatus::Single, wages: 80_000)[:tmt]).to eq(0.0)
    end

    it "phases the exemption out at 25¢/$ over the threshold" do
      result = compute(filing_status: Tax::FilingStatus::Single, wages: 400_000)
      # AMTI 400,000: exemption = 92,749 − 0.25 × (400,000 − 347,808)
      expect(result[:exemption]).to eq(79_701.0)
      expect(result[:tmt]).to eq((0.07 * (400_000 - 79_701)).round(2))
    end

    it "treats LTCG as ordinary income (no preferential rate)" do
      wages_only = compute(filing_status: Tax::FilingStatus::Single, wages: 300_000)
      with_ltcg  = compute(filing_status: Tax::FilingStatus::Single, wages: 200_000, ltcg_qd: 100_000)
      expect(with_ltcg).to eq(wages_only)
    end
  end
end
