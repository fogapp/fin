require "rails_helper"

RSpec.describe Recurring::Detector do
  def run = described_class.run

  # n charges on the same day-of-month, ending this month or last.
  def monthly_charges(merchant: nil, n: 6, amount: -15.99, day: 15, description: "SUB SERVICE")
    base = Date.current.beginning_of_month - (n - 1).months
    n.times.map do |i|
      month = base >> i
      date = Date.new(month.year, month.month, [ day, month.end_of_month.day ].min)
      next if date > Date.current

      create(:cash_transaction, :credit_card, :sale,
             merchant: merchant, description: description, amount: amount, transaction_date: date)
    end.compact
  end

  describe "detection" do
    it "suggests a monthly series grouped by merchant, with evidence occurrences" do
      merchant = create(:merchant, name: "Netflix")
      txns = monthly_charges(merchant: merchant)

      expect { run }.to change(RecurringSeries, :count).by(1)

      series = RecurringSeries.last
      expect(series.status).to eq(RecurringSeries::Status::Suggested)
      expect(series.granularity).to eq(Recurring::Schedule::Granularity::Month)
      expect(series.quantity).to eq(1)
      expect(series.anchor["day_of_month"]).to eq(15)
      expect(series.name).to eq("Netflix")
      expect(series.kind).to eq(RecurringSeries::Kind::Subscription)
      expect(series.average_amount).to be_within(0.01).of(15.99)
      expect(series.cadence_description).to eq("Monthly on the 15th")

      paid = series.recurring_occurrences.paid_like
      expect(paid.count).to eq(txns.size)
      expect(paid.pluck(:cash_transaction_id)).to match_array(txns.map(&:id))
      expect(series.recurring_occurrences.pending.count).to eq(1)
      expect(series.next_expected_date).to be > Date.current - 5.days
    end

    it "groups merchant-less charges by normalized description" do
      6.times do |i|
        create(:cash_transaction, :credit_card, :sale,
               merchant: nil, description: "NETFLIX.COM ##{1000 + i}", amount: -15.99,
               transaction_date: (Date.current.beginning_of_month >> -(5 - i)) + 14)
      end

      expect { run }.to change(RecurringSeries, :count).by(1)
      series = RecurringSeries.last
      expect(series.description_pattern).to eq("NETFLIX.COM")
      expect(series.merchant_id).to be_nil
      expect(series.name).to eq("Netflix.Com")
    end

    it "keys PayPal-processed charges on the underlying merchant" do
      6.times do |i|
        create(:cash_transaction, :credit_card, :sale,
               merchant: nil, description: "PAYPAL *SPOTIFY", amount: -10.99,
               transaction_date: (Date.current.beginning_of_month >> -(5 - i)) + 9)
      end

      run
      expect(RecurringSeries.last.description_pattern).to eq("SPOTIFY")
    end

    it "detects weekly cadence with a weekday anchor" do
      merchant = create(:merchant)
      start = Date.current - 8.weeks
      9.times do |i|
        create(:cash_transaction, :credit_card, :sale,
               merchant: merchant, amount: -9.99, transaction_date: start + (i * 7))
      end

      run
      series = RecurringSeries.last
      expect(series.granularity).to eq(Recurring::Schedule::Granularity::Week)
      expect(series.anchor["weekday"]).to eq(start.wday)
    end

    it "detects biweekly cadence" do
      merchant = create(:merchant)
      start = Date.current - 10.weeks
      6.times do |i|
        create(:cash_transaction, :credit_card, :sale,
               merchant: merchant, amount: -25.00, transaction_date: start + (i * 14))
      end

      run
      series = RecurringSeries.last
      expect(series.granularity).to eq(Recurring::Schedule::Granularity::Week)
      expect(series.quantity).to eq(2)
    end

    it "detects annual cadence from two charges" do
      merchant = create(:merchant)
      [ 1.year.ago.to_date, Date.current - 10.days ].each do |date|
        create(:cash_transaction, :credit_card, :sale,
               merchant: merchant, amount: -99.00, transaction_date: date)
      end

      run
      series = RecurringSeries.last
      expect(series&.granularity).to eq(Recurring::Schedule::Granularity::Year)
      expect(series.next_expected_date&.year).to eq(Date.current.year + 1)
    end

    it "detects month-end billing as a last-day anchor" do
      merchant = create(:merchant)
      6.times do |i|
        create(:cash_transaction, :credit_card, :sale,
               merchant: merchant, amount: -30.00,
               transaction_date: (Date.current.beginning_of_month >> -(5 - i)).end_of_month)
      end

      run
      expect(RecurringSeries.last.anchor["day_of_month"]).to eq("last")
    end

    it "detects variable bills with a widened tolerance" do
      merchant = create(:merchant, name: "City Power")
      [ -80.12, -95.40, -88.03, -105.77, -92.15, -99.60 ].each_with_index do |amt, i|
        create(:cash_transaction, :bank, :debit,
               merchant: merchant, amount: amt,
               transaction_date: (Date.current.beginning_of_month >> -(5 - i)) + 4)
      end

      run
      series = RecurringSeries.last
      expect(series.kind).to eq(RecurringSeries::Kind::Bill)
      expect(series.amount_tolerance.to_f).to be > 0.075
      expect(series.min_amount.to_f).to be_within(0.01).of(80.12)
      expect(series.max_amount.to_f).to be_within(0.01).of(105.77)
    end

    it "survives an amount outlier instead of rejecting the group" do
      merchant = create(:merchant)
      monthly_charges(merchant: merchant)
      create(:cash_transaction, :credit_card, :sale,
             merchant: merchant, amount: -45.99, transaction_date: Date.current - 40.days)

      expect { run }.to change(RecurringSeries, :count).by(1)
      series = RecurringSeries.last
      expect(series.average_amount).to be_within(0.5).of(15.99)
      expect(series.recurring_occurrences.paid_like.pluck(:amount).map(&:to_f)).not_to include(45.99)
    end

    it "splits distinct price points at one merchant into separate series" do
      merchant = create(:merchant, name: "Acme")
      monthly_charges(merchant: merchant, amount: -9.99, day: 5)
      monthly_charges(merchant: merchant, amount: -29.99, day: 20)

      expect { run }.to change(RecurringSeries, :count).by(2)
      expect(RecurringSeries.pluck(:average_amount).map(&:to_f).sort).to eq([ 9.99, 29.99 ])
    end
  end

  describe "rejection" do
    it "ignores a single charge" do
      create(:cash_transaction, :credit_card, :sale, merchant: create(:merchant), amount: -9.99)
      expect { run }.not_to change(RecurringSeries, :count)
    end

    it "ignores irregular spending with no cadence" do
      merchant = create(:merchant)
      [ 200, 170, 120, 90, 33, 7 ].each do |days_ago|
        create(:cash_transaction, :credit_card, :sale,
               merchant: merchant, amount: -42.50, transaction_date: Date.current - days_ago)
      end

      expect { run }.not_to change(RecurringSeries, :count)
    end

    it "ignores linked transfer legs (structural exclusion, like spend_like)" do
      merchant = create(:merchant)
      external = create(:account, kind: "external")
      6.times do |i|
        txn = create(:cash_transaction, :bank, :debit,
                     merchant: merchant, amount: -2400.00,
                     transaction_date: (Date.current.beginning_of_month >> -(5 - i)) + 17)
        transfer = create(:transfer, :confirmed, amount: 2400.00,
                          from_transaction_id: txn.id, from_transaction_type: "CashTransaction",
                          counterparty_account_id: external.id)
        txn.update!(transfer: transfer)
      end

      expect { run }.not_to change(RecurringSeries, :count)
    end

    it "ignores CC payment transactions" do
      merchant = create(:merchant)
      6.times do |i|
        create(:cash_transaction, :credit_card,
               merchant: merchant, amount: -200.00, transaction_type: "Payment",
               transaction_date: (Date.current.beginning_of_month >> -(5 - i)) + 14)
      end

      expect { run }.not_to change(RecurringSeries, :count)
    end

    it "ignores positive (income) transactions" do
      merchant = create(:merchant)
      6.times do |i|
        create(:cash_transaction, :bank,
               merchant: merchant, amount: 1500.00,
               transaction_date: (Date.current.beginning_of_month >> -(5 - i)) + 14)
      end

      expect { run }.not_to change(RecurringSeries, :count)
    end

    it "skips streams that already died (2+ periods stale)" do
      merchant = create(:merchant)
      6.times do |i|
        create(:cash_transaction, :credit_card, :sale,
               merchant: merchant, amount: -15.99,
               transaction_date: (Date.current.beginning_of_month >> -(11 - i)) + 14)
      end

      expect { run }.not_to change(RecurringSeries, :count)
    end
  end

  describe "durable user decisions" do
    it "is idempotent — refreshes the suggested row in place" do
      monthly_charges(merchant: create(:merchant))
      run
      expect { run }.not_to change(RecurringSeries, :count)
    end

    it "never touches a dismissed series" do
      merchant = create(:merchant)
      monthly_charges(merchant: merchant)
      run
      series = RecurringSeries.last
      series.dismiss!

      monthly_charges(merchant: merchant, n: 1)
      run
      expect(series.reload.status).to eq(RecurringSeries::Status::Dismissed)
      expect(RecurringSeries.count).to eq(1)
    end

    it "never touches an active series (the matcher owns it)" do
      merchant = create(:merchant)
      monthly_charges(merchant: merchant)
      run
      series = RecurringSeries.last
      series.accept!
      before = series.reload.updated_at

      run
      expect(series.reload.updated_at).to eq(before)
    end

    it "re-suggests an ended series when charges resume, preserving old evidence" do
      merchant = create(:merchant)
      monthly_charges(merchant: merchant, n: 4)
      run
      series = RecurringSeries.last
      old_evidence = series.recurring_occurrences.paid_like.count
      series.accept!
      series.mark_ended!
      series.update!(ended_at: 4.months.ago)

      3.times do |i|
        create(:cash_transaction, :credit_card, :sale,
               merchant: merchant, amount: -19.99,
               transaction_date: (Date.current.beginning_of_month >> -(2 - i)) + 14)
      end
      run

      expect(series.reload.status).to eq(RecurringSeries::Status::Suggested)
      expect(series.recurring_occurrences.paid_like.count).to be >= old_evidence
    end
  end

  describe "trailing lookback window" do
    it "bounds the evidence scan to LOOKBACK_MONTHS of history" do
      merchant = create(:merchant, name: "Old Timer Gym")
      monthly_charges(merchant: merchant, n: 40, amount: -50.00)

      run

      series = RecurringSeries.last
      window_start = Date.current - described_class::LOOKBACK_MONTHS.months
      expect(series.first_charge_date).to be >= window_start
      expect(series.recurring_occurrences.where("expected_date < ?", window_start)).to be_empty
    end
  end

  describe "transactional occurrence rebuild" do
    it "keeps the old evidence intact when a rebuild fails midway" do
      merchant = create(:merchant, name: "Netflix")
      monthly_charges(merchant: merchant)
      run

      series = RecurringSeries.last
      before = series.recurring_occurrences.order(:expected_date).pluck(:expected_date, :status)

      # The rebuild destroys old rows then recreates them; failing on the
      # final ("upcoming") insert must roll the whole rebuild back rather
      # than leaving the series with its paid history destroyed.
      allow_any_instance_of(RecurringOccurrence).to receive(:save!).and_wrap_original do |m, *args, **kwargs|
        raise ActiveRecord::RecordInvalid.new(m.receiver) if m.receiver.status == RecurringOccurrence::Status::Upcoming
        m.call(*args, **kwargs)
      end

      # The failure is contained per group rather than propagating: one
      # unrebuildable stream must not stop detection for every other stream
      # in the household. The rollback guarantee is unchanged — it comes from
      # the transaction inside the rebuild, not from the exception escaping.
      expect { run }.not_to raise_error
      expect(series.recurring_occurrences.order(:expected_date).pluck(:expected_date, :status))
        .to eq(before)
    end

    it "records the skipped group and keeps processing the others" do
      netflix = create(:merchant, name: "Netflix")
      spotify = create(:merchant, name: "Spotify")
      monthly_charges(merchant: netflix)
      monthly_charges(merchant: spotify, amount: -14.99, description: "SPOTIFY USA")
      run

      broken = RecurringSeries.find_by!(merchant_id: netflix.id)
      allow_any_instance_of(RecurringOccurrence).to receive(:save!).and_wrap_original do |m, *args, **kwargs|
        if m.receiver.recurring_series_id == broken.id && m.receiver.status == RecurringOccurrence::Status::Upcoming
          raise ActiveRecord::RecordInvalid.new(m.receiver)
        end

        m.call(*args, **kwargs)
      end

      stats = run

      expect(stats.failed).to eq(1)
      expect(ActivityEntry.where(event: "recurring.group_failed").count).to eq(1)
      # The healthy stream was still refreshed.
      expect(RecurringSeries.find_by!(merchant_id: spotify.id).recurring_occurrences).to be_present
    end
  end

  describe "events" do
    it "publishes subscription.suggested for new series only" do
      allow(Workflows::Events).to receive(:publish).and_call_original
      monthly_charges(merchant: create(:merchant))

      run
      expect(Workflows::Events).to have_received(:publish)
        .with("subscription.suggested", hash_including(subject: kind_of(RecurringSeries))).once

      run
      expect(Workflows::Events).to have_received(:publish)
        .with("subscription.suggested", anything).once
    end
  end
end
