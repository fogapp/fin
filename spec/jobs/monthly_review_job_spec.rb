require "rails_helper"

RSpec.describe MonthlyReviewJob, type: :job do
  let(:today)      { Date.new(2026, 8, 1) }
  let(:last_month) { Date.new(2026, 7, 1) }

  before do
    create(:workflow, trigger_type: "review.month_ready")
    Workflows::Events.reset_cache
  end

  it "publishes review.month_ready per household with last month's totals" do
    account = create(:account)
    create(:cash_transaction, :bank, :credit, account: account, amount: 4000, transaction_date: last_month + 4)
    create(:cash_transaction, :credit_card, :sale, account: account, amount: -1500, transaction_date: last_month + 10)

    travel_to(today) do
      expect { described_class.perform_now }.to have_enqueued_job(Workflows::DispatchJob).with(
        "review.month_ready",
        Current.household.id.to_s,
        "Household",
        Current.household.id.to_s,
        hash_including("month" => "2026-07", "income" => 4000.0, "spend" => 1500.0, "net" => 2500.0)
      )
    end
  end

  it "keeps sweeping when one household raises" do
    other = create(:household)
    allow(Workflows::Events).to receive(:publish).and_call_original
    allow(Workflows::Events).to receive(:publish)
      .with(anything, hash_including(subject: other)).and_raise("boom")

    travel_to(today) do
      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
