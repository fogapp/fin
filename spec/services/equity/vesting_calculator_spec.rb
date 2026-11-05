require "rails_helper"

RSpec.describe Equity::VestingCalculator do
  def calc_for(grant) = described_class.new(grant)

  describe "cumulative rounding" do
    it "splits 18 shares over 4 quarters into exact 4.5s" do
      grant = create(:equity_grant, :rsu, quantity: 18, grant_date: Date.new(2025, 1, 1),
                     vesting_interval: "quarterly", vesting_occurrences: 4, cliff_installments: 0)

      tranches = calc_for(grant).tranches
      expect(tranches.map { |t| t[:quantity] }).to all(eq(BigDecimal("4.5")))
      expect(tranches.map { |t| t[:date] }).to eq([
        Date.new(2025, 4, 1), Date.new(2025, 7, 1), Date.new(2025, 10, 1), Date.new(2026, 1, 1)
      ])
    end

    it "keeps the sum exactly equal to quantity when installments don't divide evenly" do
      grant = create(:equity_grant, :rsu, quantity: 5, grant_date: Date.new(2025, 1, 1),
                     vesting_interval: "monthly", vesting_occurrences: 3, cliff_installments: 0)

      quantities = calc_for(grant).tranches.map { |t| t[:quantity] }
      expect(quantities).to eq([ BigDecimal("1.6667"), BigDecimal("1.6666"), BigDecimal("1.6667") ])
      expect(quantities.sum).to eq(BigDecimal("5"))
    end

    it "never drifts across a long monthly schedule" do
      grant = create(:equity_grant, :rsu, quantity: 1000, grant_date: Date.new(2024, 3, 15),
                     vesting_interval: "monthly", vesting_occurrences: 48, cliff_installments: 0)

      tranches = calc_for(grant).tranches
      expect(tranches.size).to eq(48)
      expect(tranches.sum { |t| t[:quantity] }).to eq(BigDecimal("1000"))
    end
  end

  describe "cliff" do
    it "merges the first N installments into one tranche at installment N's date" do
      grant = create(:equity_grant, quantity: 4800, grant_date: Date.new(2025, 1, 1),
                     vesting_interval: "monthly", vesting_occurrences: 48, cliff_installments: 12)

      tranches = calc_for(grant).tranches
      expect(tranches.size).to eq(37)
      expect(tranches.first).to eq(date: Date.new(2026, 1, 1), quantity: BigDecimal("1200"))
      expect(tranches.second).to eq(date: Date.new(2026, 2, 1), quantity: BigDecimal("100"))
      expect(tranches.sum { |t| t[:quantity] }).to eq(BigDecimal("4800"))
    end
  end

  describe "month-end clamping" do
    it "clamps a Jan 31 commencement to Feb 28" do
      grant = create(:equity_grant, :rsu, quantity: 12, grant_date: Date.new(2025, 1, 31),
                     vesting_interval: "monthly", vesting_occurrences: 12, cliff_installments: 0)

      dates = calc_for(grant).tranches.map { |t| t[:date] }
      expect(dates.first).to eq(Date.new(2025, 2, 28))
      expect(dates.second).to eq(Date.new(2025, 3, 31))
      expect(dates.last).to eq(Date.new(2026, 1, 31))
    end
  end

  describe "custom tranches" do
    it "uses them verbatim, sorted by date, ignoring flat fields" do
      grant = create(:equity_grant, :rsu, quantity: 100, grant_date: Date.new(2025, 1, 1),
                     vesting_interval: "monthly", vesting_occurrences: 48, cliff_installments: 12,
                     custom_tranches: [
                       { "date" => "2026-01-01", "quantity" => 40 },
                       { "date" => "2025-06-01", "quantity" => 5 },
                       { "date" => "2025-12-01", "quantity" => 15 }
                     ])

      expect(calc_for(grant).tranches).to eq([
        { date: Date.new(2025, 6, 1),  quantity: BigDecimal("5") },
        { date: Date.new(2025, 12, 1), quantity: BigDecimal("15") },
        { date: Date.new(2026, 1, 1),  quantity: BigDecimal("40") }
      ])
    end
  end

  describe "no schedule" do
    it "produces a single fully-vested tranche at the commencement date" do
      grant = create(:equity_grant, :rsu, :fully_vested, quantity: 500,
                     grant_date: Date.new(2024, 5, 1))

      expect(calc_for(grant).tranches).to eq([ { date: Date.new(2024, 5, 1), quantity: BigDecimal("500") } ])
      expect(calc_for(grant).vested_quantity).to eq(BigDecimal("500"))
    end
  end

  describe "cancellation" do
    let(:grant) do
      create(:equity_grant, :rsu, quantity: 100, grant_date: Date.current - 7.months,
             vesting_interval: "quarterly", vesting_occurrences: 4, cliff_installments: 0)
    end

    it "shaves the latest tranches first" do
      create(:equity_grant_event, equity_grant: grant, kind: "cancellation",
             quantity: 30, occurred_on: Date.current)

      quantities = grant.reload.tranches.map { |t| t[:quantity] }
      expect(quantities).to eq([ BigDecimal("25"), BigDecimal("25"), BigDecimal("20") ])
    end

    it "spills into vested tranches when the unvested tail is exhausted" do
      create(:equity_grant_event, equity_grant: grant, kind: "cancellation",
             quantity: 80, occurred_on: Date.current)

      tranches = grant.reload.tranches
      expect(tranches).to eq([ { date: (grant.grant_date >> 3), quantity: BigDecimal("20") } ])
      expect(grant.vested_quantity).to eq(BigDecimal("20"))
    end
  end

  describe "as_of behavior" do
    let(:grant) do
      create(:equity_grant, :rsu, quantity: 400, grant_date: Date.new(2025, 1, 1),
             vesting_interval: "quarterly", vesting_occurrences: 4, cliff_installments: 0)
    end

    it "reports vested/unvested/next_vest as of any date" do
      calc = calc_for(grant)

      expect(calc.vested_quantity(Date.new(2025, 3, 31))).to eq(BigDecimal("0"))
      expect(calc.vested_quantity(Date.new(2025, 4, 1))).to eq(BigDecimal("100"))
      expect(calc.vested_quantity(Date.new(2025, 8, 15))).to eq(BigDecimal("200"))
      expect(calc.unvested_quantity(Date.new(2025, 8, 15))).to eq(BigDecimal("200"))
      expect(calc.next_vest(Date.new(2025, 8, 15))).to eq(date: Date.new(2025, 10, 1), quantity: BigDecimal("100"))
      expect(calc.next_vest(Date.new(2026, 1, 1))).to be_nil
    end
  end
end
