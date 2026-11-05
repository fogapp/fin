require "rails_helper"

RSpec.describe Equity::ExercisePlanner do
  let(:company) { create(:equity_company) }

  def iso_grant(quantity: 20_000, strike: 2)
    create(:equity_grant, :fully_vested, equity_company: company,
           grant_type: "iso", strike_price: strike, quantity: quantity,
           grant_date: Date.current - 2.years)
  end

  def planner_for(grant, profile, price: 22)
    described_class.new(grant: grant, profile: profile, share_price: BigDecimal(price.to_s))
  end

  describe "#crossover" do
    it "reproduces worked example 1: MFJ $332,200 wages, $2 strike / $22 FMV → 1,399 shares" do
      profile = create(:tax_profile, filing_status: "mfj", projected_wages: 332_200)
      crossover = planner_for(iso_grant, profile).crossover

      expect(crossover[:shares]).to eq(1_399)
      expect(crossover[:spread]).to be_within(50).of(27_985)
      expect(crossover[:binding]).to eq("federal")
    end

    it "is zero when the profile is already in AMT at spread 0" do
      # Big LTCG fully erodes the federal exemption: AMT before any exercise.
      profile = create(:tax_profile, projected_wages: 50_000, ltcg_qd_income: 1_000_000)
      expect(Tax::Federal.new(tax_year: 2026, filing_status: Tax::FilingStatus::Single, wages: 50_000,
                              ltcg_qd: 1_000_000).call[:amt]).to be_positive

      crossover = planner_for(iso_grant, profile).crossover
      expect(crossover[:shares]).to eq(0)
      expect(crossover[:spread]).to eq(0.0)
      expect(crossover[:binding]).to eq("federal")
    end

    it "reports California as binding when the CA headroom runs out first" do
      # Low income + LTCG: federal regular tax is inflated by the LTCG layer
      # while its TMT starts inside the 0% capital-gain bracket, so the CA
      # 7% AMT catches up to CA's small regular tax first (≈$60.8k spread
      # vs ≈$65.2k federal).
      profile = create(:tax_profile, projected_wages: 40_000, ltcg_qd_income: 40_000)
      planner = planner_for(iso_grant, profile)
      crossover = planner.crossover

      expect(crossover[:binding]).to eq("california")
      expect(crossover[:shares]).to be_within(1).of(3_039) # ≈ 60,798 spread / $20
      # At the binding crossover the federal side still has headroom.
      expect(planner.simulate(crossover[:shares].to_f)[:federal_amt]).to eq(0.0)
    end

    it "is nil for NSO grants" do
      grant = create(:equity_grant, :fully_vested, equity_company: company,
                     grant_type: "nso", strike_price: 2, quantity: 1_000,
                     grant_date: Date.current - 2.years)
      profile = create(:tax_profile)
      expect(planner_for(grant, profile).crossover).to be_nil
    end
  end

  describe "#simulate" do
    it "returns incremental AMTs, cash needed, and the next-share marginal rate" do
      profile = create(:tax_profile, filing_status: "mfj", projected_wages: 332_200)
      result = planner_for(iso_grant, profile).simulate(5_000.0)

      expect(result[:quantity]).to eq(5_000.0)
      expect(result[:spread]).to eq(100_000.0)
      # AMTI 432,200 → excess 292,000: TMT = 26%×244,500 + 28%×47,500 = 76,870;
      # incremental AMT = 76,870 − 57,196 regular = 19,674.
      expect(result[:federal_amt]).to be_within(50).of(19_674)
      expect(result[:california_amt]).to eq(0.0) # CA headroom ≈ $116k spread
      expect(result[:exercise_cost]).to eq(10_000.0)
      expect(result[:total_cash_needed])
        .to eq((result[:exercise_cost] + result[:federal_amt] + result[:california_amt]).round(2))
      expect(result[:marginal_rate_next_share]).to be_within(0.001).of(0.28) # past the 26/28 breakpoint
      expect(result[:post_exercise_agi]).to eq(332_200.0) # ISO hold leaves AGI unchanged
      expect(result[:post_exercise_federal_amti]).to eq(432_200.0)
    end
  end

  describe "#curve" do
    it "returns 41 points with a monotone non-decreasing total" do
      profile = create(:tax_profile, filing_status: "mfj", projected_wages: 332_200)
      curve = planner_for(iso_grant, profile).curve

      expect(curve.length).to eq(41)
      expect(curve.first).to eq(quantity: 0.0, federal_amt: 0.0, california_amt: 0.0, total: 0.0)
      expect(curve.last[:quantity]).to eq(20_000.0)
      totals = curve.map { |point| point[:total] }
      expect(totals).to eq(totals.sort)
      expect(totals.last).to be_positive
    end
  end

  describe "#scenarios (ISO)" do
    it "presents hold, same-year sale, and qualifying sale with non-negative taxes" do
      profile = create(:tax_profile, projected_wages: 400_000)
      scenarios = planner_for(iso_grant, profile).scenarios(10_000.0)

      hold = scenarios[:hold]
      expect(hold[:federal]).to be > 0
      expect(hold[:california]).to be > 0
      expect(hold[:note]).to match(/recoverable as a credit/)

      sale = scenarios[:same_year_sale]
      expect(sale[:federal]).to be > 0 # 200k spread as ordinary income
      expect(sale[:california]).to be > 0
      expect(sale[:proceeds]).to eq(220_000.0)

      qualifying = scenarios[:qualifying_sale]
      expect(qualifying[:exercise_year][:federal]).to eq(hold[:federal])
      expect(qualifying[:exercise_year][:california]).to eq(hold[:california])
      expect(qualifying[:sale_year][:federal]).to be > 0   # LTCG stacked on baseline
      expect(qualifying[:sale_year][:california]).to be > 0 # ordinary to CA
      # Federal sale-year tax on the gain is LTCG-rated, cheaper than CA-style ordinary treatment.
      expect(qualifying[:sale_year][:federal]).to be < 0.20 * 200_000 + 1
      expect(qualifying[:note]).to match(/8801/)
    end
  end

  describe "#nso_gap" do
    it "estimates under-withholding vs 22% federal / 10.23% CA supplemental rates" do
      grant = create(:equity_grant, :fully_vested, equity_company: company,
                     grant_type: "nso", strike_price: 2, quantity: 5_000,
                     grant_date: Date.current - 2.years)
      profile = create(:tax_profile, projected_wages: 400_000) # 35% federal / 10.3% CA marginal
      gap = planner_for(grant, profile).nso_gap(1_000.0)

      expect(gap[:spread]).to eq(20_000.0)
      expect(gap[:federal_gap]).to be_within(0.01).of(20_000 * (0.35 - 0.22))
      expect(gap[:california_gap]).to be_within(0.5).of(20_000 * (0.103 - 0.1023))
      expect(gap[:total_gap]).to eq((gap[:federal_gap] + gap[:california_gap]).round(2))
    end

    it "floors at zero when the marginal rate is below the supplemental rate" do
      grant = create(:equity_grant, :fully_vested, equity_company: company,
                     grant_type: "nso", strike_price: 2, quantity: 5_000,
                     grant_date: Date.current - 2.years)
      profile = create(:tax_profile, projected_wages: 40_000) # 12% federal < 22%
      gap = planner_for(grant, profile).nso_gap(100.0)

      expect(gap[:federal_gap]).to eq(0.0)
      expect(gap[:california_gap]).to eq(0.0)
    end

    it "is nil for ISO grants" do
      profile = create(:tax_profile)
      expect(planner_for(iso_grant, profile).nso_gap(100.0)).to be_nil
    end
  end

  describe "#safe_harbor" do
    it "is covered when withholding meets 110% of prior-year tax (high AGI)" do
      profile = create(:tax_profile, filing_status: "mfj", projected_wages: 332_200,
                       prior_year_total_tax: 50_000, prior_year_agi: 300_000,
                       ytd_withholding_federal: 56_000, ytd_withholding_state: 60_000)
      harbor = planner_for(iso_grant, profile).safe_harbor(5_000.0)

      federal = harbor[:federal]
      expect(federal[:status]).to eq("covered")
      expect(federal[:required_annual]).to eq(55_000.0) # 110% × 50,000
      expect(federal[:set_aside]).to be_within(50).of(19_674) # the incremental AMT at 5,000 shares

      california = harbor[:california]
      expect(california[:status]).to eq("covered") # 60,000 ≥ 110% × 50,000 (v1 shares one prior-year tax)
      expect(california[:installment_weights]).to eq([ 0.30, 0.40, 0.0, 0.30 ])
    end

    it "is uncovered when withholding falls short (100% multiplier under $150k AGI)" do
      profile = create(:tax_profile, projected_wages: 140_000,
                       prior_year_total_tax: 30_000, prior_year_agi: 140_000,
                       ytd_withholding_federal: 25_000)
      harbor = planner_for(iso_grant, profile).safe_harbor(1_000.0)

      expect(harbor[:federal][:status]).to eq("uncovered")
      expect(harbor[:federal][:required_annual]).to eq(30_000.0) # 100% of prior year
      expect(harbor[:federal][:set_aside]).to be_nil
    end

    it "is unknown without prior-year tax" do
      profile = create(:tax_profile, prior_year_total_tax: nil)
      harbor = planner_for(iso_grant, profile).safe_harbor(1_000.0)

      expect(harbor[:federal][:status]).to eq("unknown")
      expect(harbor[:california][:status]).to eq("unknown")
    end

    it "marks the CA safe harbor unavailable at $1M+ current-year AGI" do
      profile = create(:tax_profile, projected_wages: 1_200_000,
                       prior_year_total_tax: 100_000, prior_year_agi: 1_100_000,
                       ytd_withholding_state: 500_000)
      harbor = planner_for(iso_grant, profile).safe_harbor(1_000.0)

      expect(harbor[:california][:status]).to eq("unavailable")
      # ISO hold does not add the spread to AGI — it's the base income that trips the rule.
      expect(harbor[:california][:current_agi]).to eq(1_200_000.0)
      expect(harbor[:federal][:status]).to eq("covered").or eq("uncovered") # federal unaffected
    end
  end

  describe "#stress" do
    it "keeps the exercise-year tax fixed while the shares lose value" do
      profile = create(:tax_profile, filing_status: "mfj", projected_wages: 332_200)
      planner = planner_for(iso_grant, profile)
      stress = planner.stress(5_000.0, 60)

      expect(stress[:drop_pct]).to eq(60)
      expect(stress[:price_after]).to eq(8.8)
      expect(stress[:share_value_after]).to eq(44_000.0)
      tax = planner.simulate(5_000.0)
      expect(stress[:tax_still_owed]).to eq((tax[:federal_amt] + tax[:california_amt]).round(2))
      expect(stress[:underwater]).to eq((stress[:tax_still_owed] + 10_000 - 44_000).round(2))
    end
  end
end
