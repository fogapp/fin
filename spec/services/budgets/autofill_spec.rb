require "rails_helper"

RSpec.describe Budgets::Autofill do
  let(:month)   { Date.current.beginning_of_month }
  let(:account) { create(:account) }

  def spend!(category, amount, months_ago:)
    create(:cash_transaction, :credit_card, :sale, account: account, category: category,
           amount: -amount, transaction_date: month.months_ago(months_ago) + 3.days)
  end

  def monthly!(category, amount)
    (1..6).each { |i| spend!(category, amount, months_ago: i) }
  end

  it "budgets the few biggest categories until most spending is covered, plus everything else" do
    housing   = create(:category, name: "Housing")
    groceries = create(:category, name: "Groceries")
    dining    = create(:category, name: "Dining")
    coffee    = create(:category, name: "Coffee")
    monthly!(housing, 3000)
    monthly!(groceries, 800)
    monthly!(dining, 300)
    monthly!(coffee, 60)

    expect(described_class.call(month: month)).to eq(2)

    expect(BudgetLine.pluck(:category_id, :planned).to_h)
      .to eq(housing.id => 3000, groceries.id => 800)
    expect(BudgetLine.pluck(:mode).uniq).to eq([ BudgetLine::Mode::Ongoing ])
    expect(BudgetPeriod.in_force(month).other_planned).to eq(360)
  end

  it "rounds the typical month up to the next $5 and ignores subcategories" do
    groceries = create(:category, name: "Groceries")
    produce = create(:category, name: "Produce", parent: groceries)
    monthly!(groceries, 101)
    monthly!(produce, 20)

    described_class.call(month: month)
    expect(BudgetLine.sole).to have_attributes(category_id: groceries.id, planned: 125)
  end

  it "leaves categories already budgeted, and an existing everything-else amount, alone" do
    groceries = create(:category, name: "Groceries")
    monthly!(groceries, 800)
    BudgetLine.create!(category: groceries, month: month.prev_month, planned: 500)
    BudgetPeriod.set!(month.prev_month, other_planned: 100)

    expect(described_class.call(month: month)).to eq(0)
    expect(BudgetLine.sole.planned).to eq(500)
    expect(BudgetPeriod.in_force(month).other_planned).to eq(100)
  end
end
