require "rails_helper"

RSpec.describe Metrics::Backfill do
  let(:definition) { Metrics::Definitions::CcTransactionCount }

  it "returns 0 and writes nothing when the household has no data" do
    expect(described_class.new.call(definition)).to eq(0)
    expect(MetricPoint.count).to eq(0)
  end

  it "writes one point per month from the earliest transaction, with household_id set" do
    create(:cash_transaction, :credit_card, :sale, transaction_date: 2.months.ago.to_date)

    count = described_class.new.call(definition)

    expect(count).to eq(3) # earliest month, last month, current month
    points = MetricPoint.for_key(:cc_transaction_count).ordered
    expect(points.map(&:household_id).uniq).to eq([ Current.household.id ])
    expect(points.first.date).to eq(2.months.ago.to_date.beginning_of_month)
    expect(points.last.date).to eq(Date.current.beginning_of_month)
  end

  it "is idempotent: re-running overwrites values without duplicating rows" do
    create(:cash_transaction, :credit_card, :sale, transaction_date: Date.current)
    described_class.new.call(definition)
    expect(MetricPoint.for_key(:cc_transaction_count).ordered.last.value).to eq(1)

    create(:cash_transaction, :credit_card, :sale, transaction_date: Date.current)
    described_class.new.call(definition)

    points = MetricPoint.for_key(:cc_transaction_count)
    expect(points.where(date: Date.current.beginning_of_month).count).to eq(1)
    expect(points.ordered.last.value).to eq(2)
  end

  it "reset: true removes points the definition no longer produces" do
    create(:cash_transaction, :credit_card, :sale, transaction_date: Date.current)
    create(:metric_point, metric_key: "cc_transaction_count", date: Date.new(2010, 1, 1), value: 99)

    described_class.new.call(definition, reset: true)

    expect(MetricPoint.for_key(:cc_transaction_count).where(date: Date.new(2010, 1, 1))).to be_empty
  end

  it "stores nil values as NULL rather than skipping the period" do
    create(:cash_transaction, :credit_card, :sale, amount: -10.0, transaction_date: 1.month.ago.to_date)

    described_class.new.call(Metrics::Definitions::CcAvgTransaction)

    current = MetricPoint.for_key(:cc_avg_transaction).find_by(date: Date.current.beginning_of_month)
    expect(current).to be_present
    expect(current.value).to be_nil
  end
end
