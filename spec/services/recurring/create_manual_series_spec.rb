require "rails_helper"

RSpec.describe Recurring::CreateManualSeries do
  let(:merchant) { create(:merchant) }
  let(:schedule) do
    Recurring::Schedule.new(granularity: Recurring::Schedule::Granularity::Month, quantity: 1, anchor: {})
  end
  let(:attributes) do
    { "name" => "Streaming", "merchant_id" => merchant.id, "average_amount" => 15,
      "granularity" => "month", "quantity" => 1 }
  end

  it "creates an accepted manual series keyed by merchant with its first pending occurrence" do
    series = described_class.call(attributes: attributes, schedule: schedule)

    expect(series).to be_persisted
    expect(series).to have_attributes(
      status: RecurringSeries::Status::Active, source: RecurringSeries::Source::Manual,
      series_key: "merchant:#{merchant.id}", next_expected_date: schedule.next_on_or_after(Date.current)
    )
    expect(series.accepted_at).to be_present
    expect(series.recurring_occurrences.pending.count).to eq(1)
  end

  it "suffixes the key when the merchant already has a series" do
    described_class.call(attributes: attributes, schedule: schedule)
    second = described_class.call(attributes: attributes, schedule: schedule)

    expect(second.series_key).to start_with("merchant:#{merchant.id}:manual:")
  end

  it "schedules from the adopted transaction's date" do
    txn = create(:cash_transaction, :credit_card, :sale, merchant: merchant, transaction_date: Date.current - 10)

    series = described_class.call(attributes: attributes, schedule: schedule, adopted: txn)

    expect(series.next_expected_date).to eq(schedule.advance(txn.transaction_date))
  end

  it "leaves nothing behind when scheduling the first occurrence fails" do
    allow_any_instance_of(RecurringSeries).to receive(:recurring_occurrences).and_raise(ActiveRecord::RecordInvalid)

    expect { described_class.call(attributes: attributes, schedule: schedule) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(RecurringSeries.count).to eq(0)
  end
end
