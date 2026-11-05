# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::InstanceSettings", type: :request do
  let(:token)   { create(:api_token) }
  let(:headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/instance_settings" do
    it "requires a token" do
      get "/api/v1/instance_settings"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the zone and the selectable zones" do
      get "/api/v1/instance_settings", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["time_zone"]).to eq("America/Los_Angeles")
      expect(body["time_zones"]).to include(a_hash_including("id" => "America/New_York", "name" => "Eastern Time (US & Canada)"))
    end

    it "is readable by a non-admin member" do
      Current.user.household_memberships.update_all(role: "member")
      get "/api/v1/instance_settings", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /api/v1/instance_settings" do
    it "updates the zone" do
      patch "/api/v1/instance_settings", params: { time_zone: "Europe/Amsterdam" }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["time_zone"]).to eq("Europe/Amsterdam")
      expect(InstanceSetting.current.time_zone).to eq("Europe/Amsterdam")
      expect(InstanceSetting.time_zone).to eq("Europe/Amsterdam")
      expect(ActivityEntry.where(event: "instance.time_zone_changed")).to exist
    end

    it "stores the IANA identifier for a Rails zone name" do
      patch "/api/v1/instance_settings", params: { time_zone: "Tokyo" }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["time_zone"]).to eq("Asia/Tokyo")
    end

    it "rejects an unknown zone" do
      patch "/api/v1/instance_settings", params: { time_zone: "Mars/Olympus_Mons" }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("Time zone is not a known time zone")
      expect(InstanceSetting.time_zone).to eq("America/Los_Angeles")
    end

    it "requires the time_zone parameter" do
      patch "/api/v1/instance_settings", params: {}, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a non-admin member" do
      Current.user.household_memberships.update_all(role: "member")
      patch "/api/v1/instance_settings", params: { time_zone: "Europe/Amsterdam" }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(InstanceSetting.time_zone).to eq("America/Los_Angeles")
    end

    it "refuses a read-only token" do
      read_only = create(:api_token, scope: ApiToken::Scope::Read)
      patch "/api/v1/instance_settings", params: { time_zone: "Europe/Amsterdam" },
                                         headers: { "Authorization" => "Bearer #{read_only.raw_token}" }, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
