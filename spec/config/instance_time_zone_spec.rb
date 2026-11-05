# typed: false
# frozen_string_literal: true

require "rails_helper"

# The instance time zone (InstanceSetting) is what requests, jobs and the
# recurring schedule actually run in — not the boot default in
# config/application.rb. 22:00 PT on Dec 31 is already Jan 1 in London.
RSpec.describe "Instance time zone" do
  let(:new_years_eve_la) { Time.utc(2027, 1, 1, 6, 0, 0) } # 22:00 PST Dec 31 2026

  def set_zone(zone)
    InstanceSetting.current.update!(time_zone: zone)
  end

  describe "requests", type: :request do
    let(:token)   { create(:api_token) }
    let(:headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

    it "compute dates in the default zone" do
      travel_to(new_years_eve_la) do
        get "/api/v1/budget/calendar", headers: headers
        expect(response.parsed_body["year"]).to eq(2026)
      end
    end

    it "compute dates in the configured zone" do
      set_zone("Europe/London")
      travel_to(new_years_eve_la) do
        get "/api/v1/budget/calendar", headers: headers
        expect(response.parsed_body["year"]).to eq(2027)
      end
      # The request's zone doesn't leak out of it.
      expect(Time.zone.name).to eq("America/Los_Angeles")
    end
  end

  describe "jobs" do
    before do
      stub_const("ZoneProbeJob", Class.new(ApplicationJob) do
        cattr_accessor :seen

        def perform
          self.class.seen = [ Time.zone.tzinfo.name, Date.current ]
        end
      end)
    end

    it "run in the configured zone" do
      set_zone("Europe/London")
      travel_to(new_years_eve_la) { ZoneProbeJob.perform_now }
      expect(ZoneProbeJob.seen).to eq([ "Europe/London", Date.new(2027, 1, 1) ])
    end

    it "run in the default zone when none is configured" do
      travel_to(new_years_eve_la) { ZoneProbeJob.perform_now }
      expect(ZoneProbeJob.seen).to eq([ "America/Los_Angeles", Date.new(2026, 12, 31) ])
    end
  end

  describe "recurring schedules" do
    let(:task) { SolidQueue::RecurringTask.new(key: "probe", class_name: "PruneActivityJob", schedule: "at 2:00am every day") }

    it "resolve cron times in the configured zone" do
      travel_to(Time.utc(2026, 7, 1, 12, 0, 0)) do
        expect(task.next_time).to eq(Time.utc(2026, 7, 2, 9, 0)) # 02:00 PDT

        set_zone("Europe/London")
        expect(task.next_time).to eq(Time.utc(2026, 7, 2, 1, 0)) # 02:00 BST
      end
    end
  end
end
