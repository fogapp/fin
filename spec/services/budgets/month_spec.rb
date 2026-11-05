require "rails_helper"

RSpec.describe Budgets::Month do
  let(:month)     { Date.current.beginning_of_month }
  let(:account)   { create(:account) }
  let(:groceries) { create(:category, name: "Groceries", budget_kind: "flex") }
  let(:rent)      { create(:category, name: "Rent", budget_kind: "fixed") }

  def spend!(category, amount, date: month + 4.days)
    create(:cash_transaction, :credit_card, :sale, account: account,
           category: category, amount: -amount, transaction_date: date)
  end

  def line!(category, planned, month: self.month, rollover: false, mode: "ongoing", period: "monthly")
    BudgetLine.create!(category: category, month: month, planned: planned, rollover: rollover,
                       mode: mode, period: period)
  end

  def line_for(result, category)
    result[:lines].find { |l| l[:category_id] == category.id }
  end

  it "computes planned/actual/remaining per line and in total" do
    line!(groceries, 500)
    line!(rent, 2000)
    spend!(groceries, 320)
    spend!(rent, 2000)

    result = described_class.new(month: month).call

    expect(line_for(result, groceries)).to include(planned: 500.0, actual: 320.0, remaining: 180.0)
    expect(line_for(result, rent)[:remaining]).to eq(0.0)
    expect(result[:planned]).to eq(2500.0)
    expect(result[:actual]).to eq(2320.0)
  end

  it "carries a line set in an earlier month forward, and honors one-month overrides and stops" do
    line!(groceries, 500, month: month.months_ago(3))
    line!(groceries, 900, month: month.months_ago(2), mode: "month_only")
    line!(rent, 2000, month: month.months_ago(3))
    line!(rent, 0, month: month.months_ago(1), mode: "stopped")

    expect(line_for(described_class.new(month: month).call, groceries)).to include(planned: 500.0, set_in: month.months_ago(3).strftime("%Y-%m"))
    expect(line_for(described_class.new(month: month.months_ago(2)).call, groceries)[:planned]).to eq(900.0)
    expect(line_for(described_class.new(month: month).call, rent)).to be_nil
    expect(line_for(described_class.new(month: month.months_ago(2)).call, rent)[:planned]).to eq(2000.0)
  end

  it "measures a yearly line against spend so far this calendar year" do
    gifts = create(:category, name: "Gifts")
    line!(gifts, 1200, month: month.beginning_of_year, period: "yearly")
    spend!(gifts, 100, date: month.beginning_of_year + 3.days) unless month.month == 1
    spend!(gifts, 50)

    result = described_class.new(month: month).call
    ytd = month.month == 1 ? 50.0 : 150.0
    expect(result[:lines]).to be_empty
    expect(result[:yearly][:lines].sole).to include(planned: 1200.0, actual: ytd, month_actual: 50.0,
                                                    remaining: 1200.0 - ytd)
    expect(result[:yearly][:set_aside]).to eq(100.0)
    expect(result[:planned]).to eq(0.0)
  end

  it "reports everything else, counted in the totals only once it has an amount" do
    line!(groceries, 500)
    spend!(groceries, 100)
    spend!(create(:category, name: "Mystery"), 75)

    result = described_class.new(month: month).call
    expect(result[:everything_else]).to include(planned: nil, actual: 75.0, remaining: nil)
    expect(result[:actual]).to eq(100.0)

    BudgetPeriod.set!(month.prev_month, other_planned: 200)
    result = described_class.new(month: month).call
    expect(result[:everything_else]).to include(planned: 200.0, actual: 75.0, remaining: 125.0)
    expect(result[:planned]).to eq(700.0)
    expect(result[:actual]).to eq(175.0)
  end

  it "leaves transactions excluded from budgets out of every actual" do
    line!(groceries, 500)
    spend!(groceries, 100)
    spend!(groceries, 5000).update!(budget_excluded: true)

    expect(line_for(described_class.new(month: month).call, groceries)[:actual]).to eq(100.0)
  end

  it "takes the typical month as the median, so one big month doesn't skew it" do
    line!(groceries, 500)
    [ 400, 420, 9000, 380, 410, 390 ].each_with_index do |amount, i|
      spend!(groceries, amount, date: month.months_ago(i + 1) + 3.days)
    end

    expect(line_for(described_class.new(month: month).call, groceries)[:typical]).to eq(405.0)
  end

  it "projects the current month from pace, typical spend and pending recurring charges" do
    travel_to(month + 14.days) do
      line!(groceries, 600)
      6.times { |i| spend!(groceries, 600, date: month.months_ago(i + 1) + 3.days) }
      spend!(groceries, 450, date: month + 2.days)

      result = described_class.new(month: month).call
      line = line_for(result, groceries)
      expect(line[:projected]).to be > 600
      expect(result[:forecast]).to include(projected: line[:projected], available: 600.0)
      expect(result[:forecast][:overages].sole[:category_id]).to eq(groceries.id)
    end
  end

  it "omits the forecast for past months" do
    line!(groceries, 500, month: month.prev_month)
    expect(described_class.new(month: month.prev_month).call[:forecast]).to be_nil
  end

  it "includes subcategory spend in the parent's line unless the child has its own" do
    child = create(:category, name: "Produce", parent: groceries)
    line!(groceries, 500)
    spend!(child, 100)
    spend!(groceries, 50)

    result = described_class.new(month: month).call
    expect(result[:lines].sole[:actual]).to eq(150.0)

    line!(child, 200)
    result = described_class.new(month: month).call
    expect(line_for(result, groceries)[:actual]).to eq(50.0)
    expect(line_for(result, child)[:actual]).to eq(100.0)
  end

  it "chains rollovers through a carried-forward line: rollover(prev) + planned(prev) - actual(prev)" do
    line!(groceries, 500, month: month.months_ago(2), rollover: true)
    spend!(groceries, 400, date: month.months_ago(2) + 3.days) # +100
    spend!(groceries, 550, date: month.months_ago(1) + 3.days) # -50
    spend!(groceries, 100)

    result = described_class.new(month: month).call
    grocery_line = result[:lines].sole
    expect(grocery_line[:rollover_amount]).to eq(50.0)  # +100 - 50
    expect(grocery_line[:remaining]).to eq(450.0)       # 50 + 500 - 100
  end

  it "reports zero-based left-to-plan against the income target, net of yearly set-asides" do
    BudgetPeriod.set!(month, income_planned: 6000)
    line!(groceries, 500)
    line!(rent, 2000)
    line!(create(:category, name: "Gifts"), 1200, period: "yearly")

    result = described_class.new(month: month).call
    expect(result[:income][:planned]).to eq(6000.0)
    expect(result[:left_to_plan]).to eq(3400.0)
  end

  it "counts uncategorized spend in everything else" do
    line!(groceries, 500)
    spend!(create(:category, name: "Mystery"), 75)
    create(:cash_transaction, :credit_card, :sale, account: account,
           category: nil, amount: -25, transaction_date: month + 2.days)

    result = described_class.new(month: month).call
    expect(result[:everything_else]).to include(actual: 100.0, uncategorized: 25.0)
  end

  it "surfaces unbudgeted children rolled into a parent's actual, and clears once they have their own line" do
    child = create(:category, name: "Produce", parent: groceries)
    line!(groceries, 500)
    spend!(child, 80)
    spend!(groceries, 20)

    result = described_class.new(month: month).call
    expect(result[:lines].sole[:rolled_up_children]).to eq([ { category_id: child.id, name: "Produce", actual: 80.0 } ])

    line!(child, 100)
    result = described_class.new(month: month).call
    expect(line_for(result, groceries)[:rolled_up_children]).to eq([])
  end

  it "assembles the full payload in a bounded number of queries regardless of line count" do
    child = create(:category, name: "Produce", parent: groceries)
    line!(groceries, 500, rollover: true)
    line!(groceries, 500, month: month.months_ago(1), rollover: true)
    line!(rent, 2000)
    BudgetPeriod.set!(month, income_planned: 6000)
    spend!(groceries, 320)
    spend!(child, 40)
    spend!(rent, 2000)
    spend!(groceries, 410, date: month.months_ago(1) + 3.days)
    create(:cash_transaction, :bank, :credit, account: account, amount: 5000,
           transaction_date: month + 1.day)

    queries = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name].to_s)
      queries += 1
    end
    result = nil
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      result = described_class.new(month: month).call
    end

    # The old per-line/per-month implementation issued hundreds of aggregate
    # queries here; the memoized window queries keep it flat.
    expect(queries).to be <= 12

    grocery_line = line_for(result, groceries)
    expect(grocery_line[:actual]).to eq(360.0)          # 320 + rolled-up child 40
    expect(grocery_line[:rollover_amount]).to eq(90.0)  # 500 - 410
    expect(grocery_line[:rolled_up_children]).to eq([ { category_id: child.id, name: "Produce", actual: 40.0 } ])
    expect(result[:income][:actual]).to eq(5000.0)
    expect(result[:left_to_plan]).to eq(3500.0)
  end

  it "includes parent_name on a subcategory's line and omits it for root categories" do
    child = create(:category, name: "Produce", parent: groceries)
    line!(groceries, 500)
    line!(child, 100)

    result = described_class.new(month: month).call
    expect(line_for(result, groceries)[:parent_name]).to be_nil
    expect(line_for(result, child)[:parent_name]).to eq("Groceries")
  end
end
