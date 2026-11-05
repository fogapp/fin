require "rails_helper"

RSpec.describe Recurring::Matcher do
  def run = described_class.run

  def active_series(merchant:, amount: 15.99, expected: Date.current)
    series = create(:recurring_series, :active,
                    merchant: merchant, series_key: "merchant:#{merchant.id}",
                    average_amount: amount, last_amount: amount,
                    anchor: { "day_of_month" => expected.day },
                    next_expected_date: expected)
    create(:recurring_occurrence, recurring_series: series,
           expected_date: expected, status: "due", expected_amount: amount)
    series
  end

  it "attaches a matching charge to the pending occurrence as paid" do
    merchant = create(:merchant)
    series = active_series(merchant: merchant)
    txn = create(:cash_transaction, :credit_card, :sale,
                 merchant: merchant, amount: -15.99, transaction_date: Date.current - 1)

    run

    occ = series.recurring_occurrences.paid_like.sole
    expect(occ.status).to eq(RecurringOccurrence::Status::Paid)
    expect(occ.cash_transaction_id).to eq(txn.id)
    expect(occ.charged_date).to eq(txn.transaction_date)

    series.reload
    expect(series.last_charge_date).to eq(txn.transaction_date)
    expect(series.misses_streak).to eq(0)
    expect(series.recurring_occurrences.pending.sole.expected_date).to be > Date.current
  end

  it "matches merchant-less series by normalized description" do
    series = create(:recurring_series, :active,
                    merchant: nil, series_key: "desc:HULU", description_pattern: "HULU",
                    average_amount: 12.99, last_amount: 12.99, next_expected_date: Date.current)
    create(:recurring_occurrence, recurring_series: series,
           expected_date: Date.current, status: "due", expected_amount: 12.99)
    create(:cash_transaction, :credit_card, :sale,
           merchant: nil, description: "HULU #8371", amount: -12.99, transaction_date: Date.current)

    run
    expect(series.recurring_occurrences.paid_like.count).to eq(1)
  end

  it "marks out-of-band amounts as paid_amount_changed" do
    merchant = create(:merchant)
    series = active_series(merchant: merchant)
    create(:cash_transaction, :credit_card, :sale,
           merchant: merchant, amount: -18.99, transaction_date: Date.current)

    run
    expect(series.recurring_occurrences.paid_like.sole.status).to eq(RecurringOccurrence::Status::PaidAmountChanged)
    expect(series.reload.last_amount.to_f).to eq(18.99)
  end

  it "ignores charges too far from the expected date or amount" do
    merchant = create(:merchant)
    series = active_series(merchant: merchant)
    create(:cash_transaction, :credit_card, :sale,
           merchant: merchant, amount: -15.99, transaction_date: Date.current - 12)
    create(:cash_transaction, :credit_card, :sale,
           merchant: merchant, amount: -95.00, transaction_date: Date.current)

    run
    expect(series.recurring_occurrences.paid_like.count).to eq(0)
  end

  it "reactivates a lapsed series when a plausible charge appears" do
    merchant = create(:merchant)
    series = create(:recurring_series, :active,
                    merchant: merchant, series_key: "merchant:#{merchant.id}",
                    status: "lapsed", average_amount: 15.99, last_amount: 15.99,
                    next_expected_date: 2.months.ago.to_date)
    create(:cash_transaction, :credit_card, :sale,
           merchant: merchant, amount: -15.99, transaction_date: Date.current)

    run
    expect(series.reload.status).to eq(RecurringSeries::Status::Active)
    expect(series.recurring_occurrences.paid_like.count).to eq(1)
  end

  it "does not revive a lapsed series from a charge older than its last one" do
    merchant = create(:merchant)
    series = create(:recurring_series, :active,
                    merchant: merchant, series_key: "merchant:#{merchant.id}",
                    status: "lapsed", average_amount: 15.99, last_amount: 15.99,
                    last_charge_date: Date.current - 30, next_expected_date: Date.current - 23)
    paid_txn = create(:cash_transaction, :credit_card, :sale,
                      merchant: merchant, amount: -15.99, transaction_date: Date.current - 60)
    create(:recurring_occurrence, recurring_series: series, expected_date: Date.current - 60,
           status: "paid", cash_transaction: paid_txn, charged_date: Date.current - 60, amount: 15.99)
    # A second charge on an already-paid day — the shape that used to raise
    # "Expected date has already been taken" and discard the whole job.
    create(:cash_transaction, :credit_card, :sale,
           merchant: merchant, amount: -15.99, transaction_date: Date.current - 60)
    # Another series charged long ago widens the pool back past that charge.
    create(:recurring_series, :active, merchant: create(:merchant), last_charge_date: Date.current - 90)

    expect { run }.not_to raise_error
    expect(series.reload.status).to eq(RecurringSeries::Status::Lapsed)
    expect(series.recurring_occurrences.paid_like.count).to eq(1)
  end

  it "revives a lapsed series by paying the missed row on the charge's date" do
    merchant = create(:merchant)
    series = create(:recurring_series, :active,
                    merchant: merchant, series_key: "merchant:#{merchant.id}",
                    status: "lapsed", average_amount: 15.99, last_amount: 15.99,
                    last_charge_date: Date.current - 60, next_expected_date: Date.current - 30)
    missed = create(:recurring_occurrence, recurring_series: series,
                    expected_date: Date.current - 30, status: "missed", expected_amount: 15.99)
    txn = create(:cash_transaction, :credit_card, :sale,
                 merchant: merchant, amount: -15.99, transaction_date: Date.current - 30)

    run
    expect(series.reload.status).to eq(RecurringSeries::Status::Active)
    expect(missed.reload.status).to eq(RecurringOccurrence::Status::Paid)
    expect(missed.cash_transaction_id).to eq(txn.id)
  end

  describe "price-change events" do
    it "fires when the jump clears both thresholds ($10 and 10%)" do
      allow(Workflows::Events).to receive(:publish).and_call_original
      merchant = create(:merchant)
      series = active_series(merchant: merchant, amount: 100.00)
      create(:cash_transaction, :credit_card, :sale,
             merchant: merchant, amount: -115.00, transaction_date: Date.current)

      run
      expect(Workflows::Events).to have_received(:publish).with(
        "subscription.price_changed",
        hash_including(payload: hash_including("previous_amount" => 100.0, "new_amount" => 115.0))
      )
      expect(series.reload.last_price_change_at).to be_present
    end

    it "stays quiet for small changes" do
      allow(Workflows::Events).to receive(:publish).and_call_original
      merchant = create(:merchant)
      active_series(merchant: merchant, amount: 15.99)
      create(:cash_transaction, :credit_card, :sale,
             merchant: merchant, amount: -18.99, transaction_date: Date.current)

      run
      expect(Workflows::Events).not_to have_received(:publish).with("subscription.price_changed", anything)
    end

    it "throttles to one event per 31 days" do
      allow(Workflows::Events).to receive(:publish).and_call_original
      merchant = create(:merchant)
      series = active_series(merchant: merchant, amount: 100.00)
      series.update!(last_price_change_at: 10.days.ago)
      create(:cash_transaction, :credit_card, :sale,
             merchant: merchant, amount: -115.00, transaction_date: Date.current)

      run
      expect(Workflows::Events).not_to have_received(:publish).with("subscription.price_changed", anything)
    end
  end
end
