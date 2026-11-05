require "rails_helper"

RSpec.describe Budgets::SetLine do
  let(:month)     { Date.current.beginning_of_month }
  let(:groceries) { create(:category, name: "Groceries") }

  def planned_in(m)
    Budgets::Plan.new(through: m).line_for(groceries.id, m)&.planned
  end

  it "sets an amount from a month on, superseding later ongoing lines but keeping one-month overrides" do
    BudgetLine.create!(category: groceries, month: month.months_ago(2), planned: 400)
    BudgetLine.create!(category: groceries, month: month.next_month, planned: 450)
    BudgetLine.create!(category: groceries, month: month.months_since(2), planned: 900, mode: "month_only")

    described_class.set(category: groceries, month: month, planned: 500)

    expect(planned_in(month.months_ago(1))).to eq(400)
    expect(planned_in(month)).to eq(500)
    expect(planned_in(month.next_month)).to eq(500)
    expect(planned_in(month.months_since(2))).to eq(900)
    expect(planned_in(month.months_since(3))).to eq(500)
  end

  it "keeps the ongoing amount carrying when this month's line becomes a one-month override" do
    described_class.set(category: groceries, month: month, planned: 500)
    described_class.set(category: groceries, month: month, planned: 1500, mode: BudgetLine::Mode::MonthOnly)

    expect(planned_in(month)).to eq(1500)
    expect(planned_in(month.next_month)).to eq(500)
  end

  it "keeps rollover and period unless they're given" do
    described_class.set(category: groceries, month: month.prev_month, planned: 1200, rollover: true)
    line = described_class.set(category: groceries, month: month, planned: 1300)
    expect(line.rollover).to be(true)

    line = described_class.set(category: groceries, month: month, period: BudgetLine::Period::Yearly)
    expect(line).to have_attributes(planned: 1300, period: BudgetLine::Period::Yearly, rollover: false)
  end

  it "stops a carried line from a month on without touching the past" do
    described_class.set(category: groceries, month: month.months_ago(2), planned: 400)
    BudgetLine.create!(category: groceries, month: month.next_month, planned: 450)

    described_class.stop(category: groceries, month: month)

    expect(planned_in(month.prev_month)).to eq(400)
    expect(planned_in(month)).to be_nil
    expect(planned_in(month.months_since(3))).to be_nil
  end

  it "deletes a line set this month instead of leaving a stop marker when nothing carried into it" do
    described_class.set(category: groceries, month: month, planned: 400)
    described_class.stop(category: groceries, month: month)
    expect(BudgetLine.count).to eq(0)
  end
end
