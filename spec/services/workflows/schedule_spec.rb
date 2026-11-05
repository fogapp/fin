require "rails_helper"

RSpec.describe Workflows::Schedule do
  describe ".next_occurrence" do
    it "computes daily schedules, rolling past today's time" do
      from = Time.zone.parse("2026-07-03 10:00")
      expect(described_class.next_occurrence({ "frequency" => "daily", "at" => "05:00" }, from: from))
        .to eq(Time.zone.parse("2026-07-04 05:00"))
      expect(described_class.next_occurrence({ "frequency" => "daily", "at" => "23:30" }, from: from))
        .to eq(Time.zone.parse("2026-07-03 23:30"))
    end

    it "computes hourly intervals" do
      from = Time.zone.parse("2026-07-03 10:00")
      expect(described_class.next_occurrence({ "frequency" => "hourly", "every_hours" => 4 }, from: from))
        .to eq(Time.zone.parse("2026-07-03 14:00"))
    end

    it "computes weekly schedules (Monday=1), rolling a full week when today's slot passed" do
      friday = Time.zone.parse("2026-07-03 10:00") # 2026-07-03 is a Friday
      expect(described_class.next_occurrence(
        { "frequency" => "weekly", "day_of_week" => 1, "at" => "08:00" }, from: friday
      )).to eq(Time.zone.parse("2026-07-06 08:00"))
      expect(described_class.next_occurrence(
        { "frequency" => "weekly", "day_of_week" => 5, "at" => "08:00" }, from: friday
      )).to eq(Time.zone.parse("2026-07-10 08:00"))
    end

    it "computes monthly schedules" do
      from = Time.zone.parse("2026-07-15 10:00")
      expect(described_class.next_occurrence(
        { "frequency" => "monthly", "day_of_month" => 1, "at" => "06:00" }, from: from
      )).to eq(Time.zone.parse("2026-08-01 06:00"))
      expect(described_class.next_occurrence(
        { "frequency" => "monthly", "day_of_month" => 20, "at" => "06:00" }, from: from
      )).to eq(Time.zone.parse("2026-07-20 06:00"))
    end
  end

  describe ".validation_error" do
    it "accepts each valid shape" do
      expect(described_class.validation_error({ "frequency" => "daily", "at" => "05:00" })).to be_nil
      expect(described_class.validation_error({ "frequency" => "hourly", "every_hours" => 6 })).to be_nil
      expect(described_class.validation_error({ "frequency" => "weekly", "at" => "08:00", "day_of_week" => 7 })).to be_nil
      expect(described_class.validation_error({ "frequency" => "monthly", "at" => "08:00", "day_of_month" => 28 })).to be_nil
    end

    it "rejects malformed shapes" do
      expect(described_class.validation_error({})).to match(/frequency/)
      expect(described_class.validation_error({ "frequency" => "daily", "at" => "25:00" })).to match(/HH:MM/)
      expect(described_class.validation_error({ "frequency" => "hourly", "every_hours" => 0 })).to match(/every_hours/)
      expect(described_class.validation_error({ "frequency" => "monthly", "at" => "08:00", "day_of_month" => 31 })).to match(/1-28/)
    end
  end
end
