require "rails_helper"

RSpec.describe Recurring::Monitor do
  def run = described_class.run

  def series_with_pending(status: "active", expected:, confidence: 0.9)
    series = create(:recurring_series, status == "active" ? :active : nil,
                    status: status, confidence: confidence,
                    next_expected_date: expected).tap do |s|
      create(:recurring_occurrence, recurring_series: s,
             expected_date: expected, status: "upcoming", expected_amount: s.average_amount)
    end
    series
  end

  describe "active series" do
    it "flips upcoming to due inside the 3-day window" do
      series = series_with_pending(expected: Date.current + 2)
      run
      expect(series.recurring_occurrences.sole.status).to eq(RecurringOccurrence::Status::Due)
    end

    it "leaves far-future occurrences upcoming" do
      series = series_with_pending(expected: Date.current + 20)
      run
      expect(series.recurring_occurrences.sole.status).to eq(RecurringOccurrence::Status::Upcoming)
    end

    it "publishes subscription.charge_upcoming on the upcoming → due edge, once" do
      create(:workflow, trigger_type: "subscription.charge_upcoming")
      Workflows::Events.reset_cache
      series = series_with_pending(expected: Date.current + 2)

      expect { run }.to have_enqueued_job(Workflows::DispatchJob).with(
        "subscription.charge_upcoming",
        anything,
        "RecurringSeries",
        series.id.to_s,
        hash_including(
          "name"          => series.name,
          "expected_date" => (Date.current + 2).to_s,
          "days_until"    => 2
        )
      )

      # Already due — running again must not re-publish.
      expect { run }.not_to have_enqueued_job(Workflows::DispatchJob)
    end

    it "marks an occurrence missed past the tolerance window and schedules the next" do
      allow(Workflows::Events).to receive(:publish).and_call_original
      series = series_with_pending(expected: Date.current - 10)

      run

      series.reload
      expect(series.recurring_occurrences.missed.count).to eq(1)
      expect(series.misses_streak).to eq(1)
      expect(series).to be_at_risk
      expect(series.status).to eq(RecurringSeries::Status::Active)
      expect(series.next_expected_date).to be > Date.current - 10
      expect(Workflows::Events).to have_received(:publish).with("subscription.payment_missed", anything)
    end

    it "lapses after two consecutive misses" do
      allow(Workflows::Events).to receive(:publish).and_call_original
      series = series_with_pending(expected: Date.current - 75)

      run

      series.reload
      expect(series.status).to eq(RecurringSeries::Status::Lapsed)
      expect(series.recurring_occurrences.missed.count).to eq(2)
      expect(Workflows::Events).to have_received(:publish).with("subscription.lapsed", anything)
    end

    it "creates a pending occurrence when none exists" do
      series = create(:recurring_series, :active, next_expected_date: Date.current + 10)
      run
      expect(series.recurring_occurrences.pending.sole.expected_date).to eq(Date.current + 10)
    end
  end

  describe "suggestion sweep" do
    it "decays confidence and records the miss on a stale suggestion" do
      series = series_with_pending(status: "suggested", expected: Date.current - 10, confidence: 0.9)

      run

      series.reload
      expect(series.confidence).to be_within(0.001).of(0.63)
      expect(series.recurring_occurrences.missed.count).to eq(1)
      expect(series.status).to eq(RecurringSeries::Status::Suggested)
    end

    it "tombstones a suggestion after two missed periods" do
      series = series_with_pending(status: "suggested", expected: Date.current - 75)
      expect { run }.to change(RecurringSeries, :count).by(-1)
      expect { series.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "leaves fresh suggestions alone" do
      series = series_with_pending(status: "suggested", expected: Date.current + 5)
      run
      expect(series.reload.confidence).to eq(0.9)
    end
  end
end
