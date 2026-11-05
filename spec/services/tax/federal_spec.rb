require "rails_helper"

RSpec.describe Tax::Federal do
  def compute(**kwargs)
    described_class.new(tax_year: 2026, **kwargs).call
  end

  describe "worked example 1: MFJ, $332,200 wages, standard deduction" do
    subject(:result) { compute(filing_status: Tax::FilingStatus::Mfj, wages: 332_200) }

    it "reproduces the design-doc numbers to the dollar" do
      expect(result[:taxable_income]).to eq(300_000.0)
      expect(result[:regular_tax]).to be_within(50).of(57_196)
      expect(result[:amti]).to eq(332_200.0) # taxable + standard-deduction addback
      expect(result[:exemption]).to eq(140_200.0) # below the $1M phaseout threshold
      expect(result[:tmt]).to be_within(50).of(49_920)
      expect(result[:amt]).to eq(0.0)
      # headroom regular − TMT ≈ $7,276 → crossover spread 7,276/0.26 ≈ $27,985
      expect(result[:regular_tax] - result[:tmt]).to be_within(50).of(7_276)
    end
  end

  describe "worked example 2: single, $400k wages, itemizing, $300k ISO spread" do
    subject(:result) do
      compute(filing_status: Tax::FilingStatus::Single, wages: 400_000,
              itemizing: true, salt_paid: 50_000, iso_spread: 300_000)
    end

    it "caps SALT at $40,400 and itemizes (beats the $16,100 standard)" do
      expect(result[:salt_used]).to eq(40_400.0)
      expect(result[:taxable_income]).to eq(359_600.0)
    end

    it "reproduces the design-doc AMT to the dollar" do
      expect(result[:regular_tax]).to be_within(200).of(94_600)
      expect(result[:amti]).to eq(700_000.0) # taxable + SALT addback + spread
      expect(result[:exemption]).to eq(0.0)  # 50% × $200k over threshold ≥ $90,100
      expect(result[:tmt]).to be_within(50).of(191_110) # 26%×244,500 + 28%×455,500
      expect(result[:amt]).to be_within(50).of(result[:tmt] - result[:regular_tax])
      expect(result[:amt]).to be_within(200).of(96_500)
    end
  end

  describe "ordinary bracket edges" do
    it "taxes exactly the top of the 10% bracket at 10%" do
      # wages 28,500 − 16,100 standard = taxable 12,400 (the 10% top)
      expect(compute(filing_status: Tax::FilingStatus::Single, wages: 28_500)[:regular_tax]).to eq(1_240.0)
    end

    it "taxes the next dollar at 12%" do
      expect(compute(filing_status: Tax::FilingStatus::Single, wages: 28_600)[:regular_tax])
        .to eq(1_240.0 + 0.12 * 100)
    end
  end

  describe "AMT 26/28 rate breakpoint" do
    it "switches to 28% above $244,500 of taxable excess" do
      # Standard deduction ⇒ AMTI == wages; excess = wages − 90,100.
      at_breakpoint = compute(filing_status: Tax::FilingStatus::Single, wages: 334_600)[:tmt] # excess 244,500
      above         = compute(filing_status: Tax::FilingStatus::Single, wages: 335_600)[:tmt]
      expect(at_breakpoint).to eq((0.26 * 244_500).round(2))
      expect(above - at_breakpoint).to be_within(0.01).of(0.28 * 1_000)
    end
  end

  describe "exemption phaseout band marginal rates" do
    it "is 42% (28% × 1.5) on spread when the excess is past the 26/28 breakpoint" do
      base = compute(filing_status: Tax::FilingStatus::Single, wages: 400_000, iso_spread: 150_000) # AMTI 550k, in band
      more = compute(filing_status: Tax::FilingStatus::Single, wages: 400_000, iso_spread: 151_000)
      expect((more[:tmt] - base[:tmt]) / 1_000).to be_within(0.001).of(0.42)
    end

    it "is 39% (26% × 1.5) when big LTCG keeps the non-LTCG excess under the breakpoint" do
      base = compute(filing_status: Tax::FilingStatus::Single, wages: 210_000, ltcg_qd: 300_000, iso_spread: 0) # AMTI 510k
      more = compute(filing_status: Tax::FilingStatus::Single, wages: 210_000, ltcg_qd: 300_000, iso_spread: 1_000)
      expect((more[:tmt] - base[:tmt]) / 1_000).to be_within(0.001).of(0.39)
    end
  end

  describe "Part III capital-gain preservation" do
    it "taxes LTCG at its preferential rate inside TMT below the phaseout" do
      base = compute(filing_status: Tax::FilingStatus::Mfj, wages: 332_200)
      with = compute(filing_status: Tax::FilingStatus::Mfj, wages: 332_200, ltcg_qd: 10_000)
      # 15% × 10,000 = 1,500 — never 26% × 10,000.
      expect(with[:tmt] - base[:tmt]).to eq(1_500.0)
      expect(with[:regular_tax] - base[:regular_tax]).to eq(1_500.0)
    end
  end

  describe "SALT cap phase-down" do
    it "phases the cap down 30¢/$ of MAGI over $505k" do
      result = compute(filing_status: Tax::FilingStatus::Single, wages: 555_000, itemizing: true, salt_paid: 40_400)
      expect(result[:salt_used]).to eq(25_400.0) # 40,400 − 0.3 × 50,000
      expect(result[:taxable_income]).to eq(529_600.0)
    end

    it "floors the cap at $10,000 for high MAGI" do
      result = compute(filing_status: Tax::FilingStatus::Single, wages: 700_000,
                       itemizing: true, salt_paid: 50_000, itemized_other: 20_000)
      expect(result[:salt_used]).to eq(10_000.0)
      expect(result[:taxable_income]).to eq(670_000.0) # 700k − (10k + 20k)
    end

    it "falls back to the standard deduction when itemized totals lose" do
      result = compute(filing_status: Tax::FilingStatus::Single, wages: 700_000, itemizing: true, salt_paid: 50_000)
      # Capped SALT of 10,000 alone < 16,100 standard: standard wins, no SALT used.
      expect(result[:salt_used]).to eq(0.0)
      expect(result[:taxable_income]).to eq(683_900.0)
    end
  end
end
