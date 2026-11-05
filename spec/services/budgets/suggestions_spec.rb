require "rails_helper"

RSpec.describe Budgets::Suggestions do
  let(:month)   { Date.current.beginning_of_month }
  let(:account) { create(:account) }
  let(:home)    { create(:category, name: "Home") }

  def spend!(category, amount, months_ago:, description: "Charge")
    create(:cash_transaction, :credit_card, :sale, account: account, category: category, description: description,
           amount: -amount, transaction_date: month.months_ago(months_ago) + 3.days)
  end

  it "suggests the median month and lists the one-off charges it leaves out" do
    [ 300, 320, 280, 310, 290 ].each_with_index { |a, i| spend!(home, a, months_ago: i + 1) }
    spend!(home, 28_970, months_ago: 6, description: "Design firm")

    row = described_class.new(month: month).call[:categories].sole
    expect(row).to include(typical: 305.0, suggested: 305, year_total: 30_470.0)
    expect(row[:history].map { |h| h[:actual] }).to eq([ 28_970.0, 290.0, 310.0, 280.0, 320.0, 300.0 ])
    expect(row[:unusual].sole).to include(description: "Design firm", amount: 28_970.0)
  end

  it "rolls unbudgeted subcategories into the parent, and lists the subcategory too" do
    repairs = create(:category, name: "Repairs", parent: home)
    (1..6).each { |i| spend!(repairs, 100, months_ago: i) }

    rows = described_class.new(month: month).call[:categories]
    expect(rows.find { |r| r[:category_id] == home.id }[:typical]).to eq(100.0)
    expect(rows.find { |r| r[:category_id] == repairs.id }).to include(parent_name: "Home", typical: 100.0)
  end

  it "leaves a subcategory budgeted on its own out of the parent" do
    repairs = create(:category, name: "Repairs", parent: home)
    (1..6).each { |i| spend!(repairs, 100, months_ago: i) }
    (1..6).each { |i| spend!(home, 40, months_ago: i) }
    BudgetLine.create!(category: repairs, month: month, planned: 100)

    rows = described_class.new(month: month).call
    expect(rows[:categories].find { |r| r[:category_id] == home.id }[:typical]).to eq(40.0)
    expect(rows[:everything_else][:typical]).to eq(40.0)
  end

  it "floors the suggestion at the category's recurring charges" do
    streaming = create(:category, name: "Streaming")
    (1..6).each { |i| spend!(streaming, 5, months_ago: i) }
    series = create(:recurring_series, :active, name: "Service", average_amount: 30)
    txn = spend!(streaming, 30, months_ago: 1)
    create(:recurring_occurrence, :paid, recurring_series: series, cash_transaction: txn)

    row = described_class.new(month: month).call[:categories].sole
    expect(row[:recurring_monthly]).to be >= 30
    expect(row[:suggested]).to be >= 30
  end
end
