# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceSetting do
  describe "time_zone" do
    it "defaults to America/Los_Angeles" do
      expect(described_class.current.time_zone).to eq("America/Los_Angeles")
    end

    it "accepts an IANA identifier" do
      setting = described_class.current
      setting.update!(time_zone: "Europe/Amsterdam")
      expect(setting.reload.time_zone).to eq("Europe/Amsterdam")
    end

    it "stores the IANA identifier for a Rails zone name" do
      setting = described_class.current
      setting.update!(time_zone: "Eastern Time (US & Canada)")
      expect(setting.reload.time_zone).to eq("America/New_York")
    end

    it "rejects an unknown zone" do
      setting = described_class.current
      setting.time_zone = "Mars/Olympus_Mons"
      expect(setting).not_to be_valid
      expect(setting.errors[:time_zone]).to include("is not a known time zone")
    end

    it "rejects a blank zone" do
      setting = described_class.current
      setting.time_zone = ""
      expect(setting).not_to be_valid
    end
  end

  describe ".time_zone" do
    it "reads the default without creating the row" do
      expect(described_class.time_zone).to eq("America/Los_Angeles")
      expect(described_class.count).to eq(0)
    end

    it "memoizes the lookup and drops the memo when the zone is saved" do
      expect(described_class.time_zone).to eq("America/Los_Angeles")

      # A write that bypasses the model (another process, say) is only seen
      # once the memo expires…
      described_class.current.update_column(:time_zone, "Asia/Tokyo")
      expect(described_class.time_zone).to eq("America/Los_Angeles")

      # …but a save through the model drops this process's copy at once.
      described_class.current.update!(time_zone: "Europe/London")
      expect(described_class.time_zone).to eq("Europe/London")
    end

    it "re-reads once the memo expires" do
      expect(described_class.time_zone).to eq("America/Los_Angeles")
      described_class.current.update_column(:time_zone, "Asia/Tokyo")

      later = Process.clock_gettime(Process::CLOCK_MONOTONIC) + InstanceSetting::TIME_ZONE_CACHE_TTL + 1
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(later)
      expect(described_class.time_zone).to eq("Asia/Tokyo")
    end
  end

  describe ".selectable_time_zones" do
    it "lists IANA location zones with Rails names and current offsets" do
      zones = described_class.selectable_time_zones
      la = zones.find { |z| z[:id] == "America/Los_Angeles" }
      expect(la).to include(name: "Pacific Time (US & Canada)")
      expect(la[:utc_offset]).to match(/\A-0[78]:00\z/)
      expect(zones.map { |z| z[:id] }).to include("Etc/UTC", "Europe/Amsterdam")
      expect(zones.map { |z| z[:id] }).not_to include("US/Pacific")
    end
  end

  describe "changing the zone" do
    it "moves pending daily schedules to the same wall-clock time in the new zone" do
      workflow = nil
      travel_to Time.utc(2026, 7, 1, 12, 0, 0) do
        Time.use_zone("America/Los_Angeles") do
          workflow = create(:workflow, trigger_type: Workflows::Catalog::SCHEDULE_TRIGGER,
                                       trigger_config: { "frequency" => "daily", "at" => "05:30" })
        end
        # It is 05:00 PDT: next is 05:30 PDT today
        expect(workflow.reload.next_scheduled_at).to eq(Time.utc(2026, 7, 1, 12, 30))

        described_class.current.update!(time_zone: "America/New_York")
        # It is 08:00 EDT: next is 05:30 EDT tomorrow
        expect(workflow.reload.next_scheduled_at).to eq(Time.utc(2026, 7, 2, 9, 30))
      end
    end

    it "leaves hourly schedules alone" do
      travel_to Time.utc(2026, 7, 1, 12, 0, 0) do
        workflow = create(:workflow, trigger_type: Workflows::Catalog::SCHEDULE_TRIGGER,
                                     trigger_config: { "frequency" => "hourly", "every_hours" => 4 })
        expect { described_class.current.update!(time_zone: "Asia/Tokyo") }
          .not_to(change { workflow.reload.next_scheduled_at })
      end
    end
  end
end
