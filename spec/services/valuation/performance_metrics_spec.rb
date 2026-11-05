require "rails_helper"

RSpec.describe Valuation::PerformanceMetrics do
  def metrics(values, flows = {})
    described_class.new(values: values, flows: flows)
  end

  describe "#twr" do
    it "returns nil with fewer than two points" do
      expect(metrics({ Date.new(2026, 1, 1) => 100.0 }).twr).to be_nil
    end

    it "computes simple growth with no flows" do
      values = {
        Date.new(2026, 1, 1) => 100.0,
        Date.new(2026, 1, 2) => 110.0,
        Date.new(2026, 1, 3) => 121.0
      }
      expect(metrics(values).twr).to be_within(1e-9).of(0.21)
    end

    it "removes the effect of a mid-period contribution" do
      # Flat prices; a 100 deposit doubles the value but earns nothing.
      values = {
        Date.new(2026, 1, 1) => 100.0,
        Date.new(2026, 1, 2) => 200.0,
        Date.new(2026, 1, 3) => 200.0
      }
      flows = { Date.new(2026, 1, 2) => 100.0 }
      expect(metrics(values, flows).twr).to be_within(1e-9).of(0.0)
    end

    it "removes the effect of a withdrawal" do
      # 10% gain on day 2, then half withdrawn: TWR stays 10%.
      values = {
        Date.new(2026, 1, 1) => 100.0,
        Date.new(2026, 1, 2) => 110.0,
        Date.new(2026, 1, 3) => 55.0
      }
      flows = { Date.new(2026, 1, 3) => -55.0 }
      expect(metrics(values, flows).twr).to be_within(1e-9).of(0.10)
    end

    it "skips days where the flow-adjusted base is non-positive" do
      values = {
        Date.new(2026, 1, 1) => 100.0,
        Date.new(2026, 1, 2) => 50.0,
        Date.new(2026, 1, 3) => 55.0
      }
      flows = { Date.new(2026, 1, 2) => -100.0 } # full liquidation recorded same day
      expect(metrics(values, flows).twr).to be_within(1e-9).of(0.10)
    end
  end

  describe "#twr_annualized" do
    it "leaves sub-year windows unannualized" do
      values = {
        Date.new(2026, 1, 1) => 100.0,
        Date.new(2026, 3, 1) => 105.0
      }
      m = metrics(values)
      expect(m.twr_annualized).to eq(m.twr)
    end

    it "annualizes multi-year windows geometrically" do
      values = {
        Date.new(2024, 1, 1) => 100.0,
        Date.new(2026, 1, 1) => 144.0 # ~2 years, 44% total
      }
      annualized = metrics(values).twr_annualized
      # (1.44)^(365/731) - 1 ≈ 19.9%
      expect(annualized).to be_within(0.005).of(0.199)
    end
  end

  describe "#xirr" do
    it "matches the simple annual return for a flowless year" do
      values = {
        Date.new(2025, 1, 1) => 100.0,
        Date.new(2026, 1, 1) => 110.0
      }
      expect(metrics(values).xirr).to be_within(1e-4).of(0.10)
    end

    it "weights a late contribution's return by its time in market" do
      # 1000 all year earning nothing; 1000 more added a day before the end.
      values = {
        Date.new(2025, 1, 1) => 1000.0,
        Date.new(2025, 12, 31) => 2000.0
      }
      flows = { Date.new(2025, 12, 30) => 1000.0 }
      expect(metrics(values, flows).xirr).to be_within(1e-3).of(0.0)
    end

    it "returns nil when every flow has the same sign" do
      values = {
        Date.new(2025, 1, 1) => 0.0,
        Date.new(2026, 1, 1) => 0.0
      }
      expect(metrics(values).xirr).to be_nil
    end

    it "recovers a known rate from a contribution schedule" do
      # 100 at t0, +100 at 6 months, ending value computed at exactly 8%.
      rate = 0.08
      half_year_factor = (1 + rate)**(184.0 / 365.0)
      values = {
        Date.new(2025, 1, 1) => 100.0,
        Date.new(2026, 1, 1) => (100.0 * (1 + rate) + 100.0 * half_year_factor).round(6)
      }
      flows = { Date.new(2025, 7, 1) => 100.0 }
      expect(metrics(values, flows).xirr).to be_within(1e-3).of(rate)
    end
  end

  describe "#net_flows" do
    it "sums flows strictly inside the window" do
      values = {
        Date.new(2026, 1, 1) => 100.0,
        Date.new(2026, 1, 10) => 100.0
      }
      flows = {
        Date.new(2026, 1, 1) => 999.0,  # on the start date: outside
        Date.new(2026, 1, 5) => 50.0,
        Date.new(2026, 1, 10) => -20.0,
        Date.new(2026, 1, 11) => 999.0  # after the end: outside
      }
      expect(metrics(values, flows).net_flows).to eq(30.0)
    end
  end
end
