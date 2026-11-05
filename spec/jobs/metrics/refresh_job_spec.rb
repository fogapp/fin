require "rails_helper"

RSpec.describe Metrics::RefreshJob do
  it "backfills metrics with no stored points and keeps households isolated" do
    create(:cash_transaction, :credit_card, :sale, transaction_date: Date.current)

    other_household = Household.create!(name: "Other")
    other_account   = nil
    Current.set(household: other_household) do
      other_account = create(:account)
      create(:cash_transaction, :credit_card, :sale, account: other_account,
             transaction_date: Date.current)
      create(:cash_transaction, :credit_card, :sale, account: other_account,
             transaction_date: Date.current)
    end

    described_class.perform_now

    mine   = MetricPoint.unscoped.where(household_id: Current.household.id, metric_key: "cc_transaction_count")
    theirs = MetricPoint.unscoped.where(household_id: other_household.id, metric_key: "cc_transaction_count")
    expect(mine.find_by(date: Date.current.beginning_of_month).value).to eq(1)
    expect(theirs.find_by(date: Date.current.beginning_of_month).value).to eq(2)
  end

  it "picks up late-arriving transactions inside the trailing window" do
    create(:cash_transaction, :credit_card, :sale, transaction_date: 1.month.ago.to_date)
    described_class.perform_now

    last_month = 1.month.ago.to_date.beginning_of_month
    expect(point_value(last_month)).to eq(1)

    # A transaction lands late for last month; the next refresh corrects it.
    create(:cash_transaction, :credit_card, :sale, transaction_date: 1.month.ago.to_date)
    described_class.perform_now

    expect(point_value(last_month)).to eq(2)
  end

  it "continues past a failing definition" do
    create(:cash_transaction, :credit_card, :sale, transaction_date: Date.current)
    allow_any_instance_of(Metrics::Definitions::MonthlySpend)
      .to receive(:series).and_raise("boom")

    expect { described_class.perform_now }.not_to raise_error
    expect(MetricPoint.unscoped.where(metric_key: "cc_transaction_count")).to be_present
  end

  def point_value(date)
    MetricPoint.unscoped
      .where(household_id: Current.household.id, metric_key: "cc_transaction_count", date: date)
      .pick(:value)
  end
end
