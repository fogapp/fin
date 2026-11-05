require "rails_helper"

RSpec.describe Recurring::Schedule do
  describe "#advance" do
    it "advances weekly preserving weekday" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Week, anchor: { "weekday" => 5 })
      expect(schedule.advance(Date.new(2026, 1, 2))).to eq(Date.new(2026, 1, 9))
    end

    it "advances biweekly" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Week, quantity: 2, anchor: { "weekday" => 5 })
      expect(schedule.advance(Date.new(2026, 1, 2))).to eq(Date.new(2026, 1, 16))
    end

    it "advances monthly on a fixed day" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Month, anchor: { "day_of_month" => 15 })
      expect(schedule.advance(Date.new(2026, 1, 15))).to eq(Date.new(2026, 2, 15))
    end

    it "clamps day-of-month to short months" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Month, anchor: { "day_of_month" => 31 })
      expect(schedule.advance(Date.new(2026, 1, 31))).to eq(Date.new(2026, 2, 28))
    end

    it "handles last-day-of-month" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Month, anchor: { "day_of_month" => "last" })
      expect(schedule.advance(Date.new(2026, 1, 31))).to eq(Date.new(2026, 2, 28))
      expect(schedule.advance(Date.new(2026, 2, 28))).to eq(Date.new(2026, 3, 31))
    end

    it "handles nth-weekday (3rd Friday)" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Month, anchor: { "nth_weekday" => [ 3, 5 ] })
      expect(schedule.advance(Date.new(2026, 1, 16))).to eq(Date.new(2026, 2, 20))
    end

    it "advances quarterly" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Month, quantity: 3, anchor: { "day_of_month" => 12 })
      expect(schedule.advance(Date.new(2026, 1, 12))).to eq(Date.new(2026, 4, 12))
    end

    it "advances yearly on a fixed month/day" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Year, anchor: { "month" => 11, "day" => 3 })
      expect(schedule.advance(Date.new(2025, 11, 3))).to eq(Date.new(2026, 11, 3))
    end
  end

  describe "#dates_between" do
    it "materializes expected dates after the seed" do
      schedule = described_class.new(granularity: Recurring::Schedule::Granularity::Month, anchor: { "day_of_month" => 10 })
      dates = schedule.dates_between(Date.new(2026, 1, 10), Date.new(2026, 4, 30))
      expect(dates).to eq([ Date.new(2026, 2, 10), Date.new(2026, 3, 10), Date.new(2026, 4, 10) ])
    end
  end

  describe "#description" do
    it "describes cadences in words" do
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Week, anchor: { "weekday" => 5 }).description).to eq("Weekly on Friday")
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Week, quantity: 2, anchor: { "weekday" => 1 }).description).to eq("Every 2 weeks on Monday")
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Month, anchor: { "day_of_month" => 15 }).description).to eq("Monthly on the 15th")
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Month, anchor: { "day_of_month" => "last" }).description).to eq("Monthly on the last day")
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Month, quantity: 3, anchor: { "day_of_month" => 1 }).description).to eq("Every 3 months on the 1st")
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Month, anchor: { "nth_weekday" => [ 3, 5 ] }).description).to eq("Monthly on the 3rd Friday")
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Year, anchor: { "month" => 11, "day" => 3 }).description).to eq("Yearly on Nov 3")
    end
  end

  describe "#periods_per_year" do
    it "reflects granularity and quantity" do
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Week).periods_per_year).to eq(52.0)
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Week, quantity: 2).periods_per_year).to eq(26.0)
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Month, quantity: 3).periods_per_year).to eq(4.0)
      expect(described_class.new(granularity: Recurring::Schedule::Granularity::Year).periods_per_year).to eq(1.0)
    end
  end
end
