require "rails_helper"

RSpec.describe RecurringSeries do
  describe "lifecycle transitions" do
    it "accepts a suggestion" do
      series = create(:recurring_series)
      series.accept!
      expect(series.status).to eq(RecurringSeries::Status::Active)
      expect(series.accepted_at).to be_present
    end

    it "dismisses a suggestion" do
      series = create(:recurring_series)
      series.dismiss!
      expect(series.status).to eq(RecurringSeries::Status::Dismissed)
      expect(series.dismissed_at).to be_present
    end

    it "ends an active series" do
      series = create(:recurring_series, :active)
      series.mark_ended!
      expect(series.status).to eq(RecurringSeries::Status::Ended)
      expect(series.ended_at).to be_present
    end

    it "restores a dismissed series to suggested" do
      series = create(:recurring_series)
      series.dismiss!
      series.restore!
      expect(series.status).to eq(RecurringSeries::Status::Suggested)
    end

    it "restores an ended series to active" do
      series = create(:recurring_series, :active)
      series.mark_ended!
      series.restore!
      expect(series.status).to eq(RecurringSeries::Status::Active)
    end

    it "rejects invalid transitions" do
      series = create(:recurring_series)
      expect { series.mark_ended! }.to raise_error(RecurringSeries::InvalidTransition, /cannot move suggested/)
    end

    it "gives an accepted series a pending forecast" do
      series = create(:recurring_series)
      expect { series.accept! }.to change { series.recurring_occurrences.pending.count }.from(0).to(1)
    end

    it "drops pending forecasts when a series stops being tracked" do
      series = create(:recurring_series, :active)
      create(:recurring_occurrence, recurring_series: series, status: "upcoming")
      series.mark_ended!
      expect(series.recurring_occurrences.pending).to be_empty
    end

    it "rolls the transition back when the side effect fails" do
      series = create(:recurring_series)
      allow(series).to receive(:ensure_pending_occurrence!).and_raise(ActiveRecord::RecordInvalid)
      expect { series.accept! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(series.reload.status).to eq(RecurringSeries::Status::Suggested)
    end

    it "resets the misses streak on transition" do
      series = create(:recurring_series, :active, misses_streak: 2)
      series.transition_to!(RecurringSeries::Status::Lapsed)
      expect(series.misses_streak).to eq(0)
    end
  end

  describe "#monthly_equivalent" do
    it "normalizes by cadence" do
      expect(build(:recurring_series, average_amount: 12).monthly_equivalent).to be_within(0.01).of(12)
      expect(build(:recurring_series, :weekly, average_amount: 12).monthly_equivalent).to be_within(0.01).of(52.0)
      expect(build(:recurring_series, :annual, average_amount: 120).monthly_equivalent).to be_within(0.01).of(10)
      expect(build(:recurring_series, granularity: "month", quantity: 3, average_amount: 30).monthly_equivalent).to be_within(0.01).of(10)
    end
  end

  describe "#amount_band" do
    it "spans the tolerance around the average" do
      series = build(:recurring_series, average_amount: 100, amount_tolerance: 0.075)
      expect(series.amount_band).to eq(92.5..107.5)
    end

    it "allows at least a dollar of slack for small amounts" do
      series = build(:recurring_series, average_amount: 3, amount_tolerance: 0.075)
      expect(series.amount_band).to eq(2.0..4.0)
    end
  end

  describe "#at_risk?" do
    it "is true only for active series with exactly one miss" do
      expect(build(:recurring_series, :active, misses_streak: 1)).to be_at_risk
      expect(build(:recurring_series, :active, misses_streak: 0)).not_to be_at_risk
      expect(build(:recurring_series, misses_streak: 1)).not_to be_at_risk
    end
  end

  describe "series_key uniqueness" do
    it "is scoped to household" do
      existing = create(:recurring_series)
      dupe = build(:recurring_series, household: existing.household, series_key: existing.series_key)
      expect(dupe).not_to be_valid
    end
  end
end
