require "rails_helper"

RSpec.describe Budgets::CheckThresholds do
  let(:month)     { Date.current.beginning_of_month }
  let(:account)   { create(:account) }
  let(:groceries) { create(:category, name: "Groceries") }

  before do
    BudgetLine.create!(household_id: Current.household.id, category: groceries,
                       month: month, planned: 100)
    create(:workflow, trigger_type: "budget.category_exceeded")
    create(:workflow, name: "Approaching", trigger_type: "budget.category_approaching")
    Workflows::Events.reset_cache
  end

  def spend!(amount)
    create(:cash_transaction, :credit_card, :sale, account: account,
           category: groceries, amount: -amount, transaction_date: Date.current)
  end

  it "publishes approaching at 90% and exceeded at 100%, each once" do
    txn = spend!(85)
    expect { described_class.call(txn) }.not_to have_enqueued_job(Workflows::DispatchJob)

    txn = spend!(10) # 95%
    expect { described_class.call(txn) }
      .to have_enqueued_job(Workflows::DispatchJob)
      .with("budget.category_approaching", anything, "Category", groceries.id.to_s, anything)

    txn = spend!(2) # 97% — approaching already alerted
    expect { described_class.call(txn) }.not_to have_enqueued_job(Workflows::DispatchJob)

    txn = spend!(10) # 107%
    expect { described_class.call(txn) }
      .to have_enqueued_job(Workflows::DispatchJob)
      .with("budget.category_exceeded", anything, "Category", groceries.id.to_s, anything)

    txn = spend!(5)
    expect { described_class.call(txn) }.not_to have_enqueued_job(Workflows::DispatchJob)
  end

  it "resolves a subcategory transaction to the parent's budget line" do
    child = create(:category, name: "Produce", parent: groceries)
    txn = create(:cash_transaction, :credit_card, :sale, account: account,
                 category: child, amount: -95, transaction_date: Date.current)

    expect { described_class.call(txn) }
      .to have_enqueued_job(Workflows::DispatchJob)
      .with("budget.category_approaching", anything, "Category", groceries.id.to_s, anything)
  end

  it "enqueues the check from transaction commits" do
    expect {
      spend!(10)
    }.to have_enqueued_job(Budgets::CheckThresholdsJob)
  end

  it "ignores transactions outside the current month" do
    txn = create(:cash_transaction, :credit_card, :sale, account: account,
                 category: groceries, amount: -500, transaction_date: 2.months.ago.to_date)
    expect { described_class.call(txn) }.not_to have_enqueued_job(Workflows::DispatchJob)
  end

  it "alerts again in a new month on a line carried forward from an earlier one" do
    line = BudgetLine.sole
    line.update!(month: month.prev_month, exceeded_alerted_at: 1.month.ago, approaching_alerted_at: 1.month.ago)

    txn = spend!(120)
    expect { described_class.call(txn) }
      .to have_enqueued_job(Workflows::DispatchJob)
      .with("budget.category_exceeded", anything, "Category", groceries.id.to_s, anything)
  end

  it "ignores transactions excluded from budgets" do
    txn = spend!(500)
    txn.update!(budget_excluded: true)
    expect { described_class.call(txn) }.not_to have_enqueued_job(Workflows::DispatchJob)
  end
end
