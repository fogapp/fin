# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Backups", type: :request do
  include ActiveJob::TestHelper

  let(:token)   { create(:api_token) }
  let(:headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  after { FileUtils.rm_rf(FogBackup::Staging.root) }

  def stage(job_id, status: "completed", origin: "manual")
    FogBackup::Staging.write_status(job_id, status, meta: { "origin" => origin, "requested_by" => "test@example.com" })
    return unless status == "completed"

    FogBackup::Staging.artifact_path(job_id).write("tar bytes")
    FogBackup::Staging.artifact_info_path(job_id).write(
      { bytes: 9, sha256: "abc", created_at: "2026-09-30T12:00:00Z" }.to_json
    )
  end

  describe "who may use it" do
    it "requires a token" do
      get "/api/v1/backups"
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a non-admin member" do
      Current.user.household_memberships.update_all(role: "member")
      get "/api/v1/backups", headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    # A backup is instance-wide, and the admin of any household may take one.
    it "serves the admin of a household founded later than the first" do
      travel_to(1.day.ago) { create(:household, name: "Default") }
      later = create(:household)
      admin = create(:user)
      create(:household_membership, user: admin, household: later, role: "admin")
      admin_token = create(:api_token, user: admin, household: later)

      get "/api/v1/backups", headers: { "Authorization" => "Bearer #{admin_token.raw_token}" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/backups" do
    it "lists manual backups newest first and leaves fog's own jobs out" do
      travel_to(2.minutes.ago) { stage("aaa111") }
      stage("bbb222", status: "running")
      stage("f09f09", origin: "fog")

      get "/api/v1/backups", headers: headers

      body = response.parsed_body
      expect(body["backups"].map { |b| b["id"] }).to eq(%w[bbb222 aaa111])
      expect(body["backups"].last).to include(
        "status" => "completed", "bytes" => 9, "sha256" => "abc",
        "filename" => "fin-20260930-120000.fogpack.tar", "requested_by" => "test@example.com"
      )
      expect(body["retention_hours"]).to eq(24)
    end

    it "reports the address an artifact produced here is bound to" do
      host! "fin.example.com"
      get "/api/v1/backups", headers: headers
      expect(response.parsed_body["address"]).to eq("host" => "fin.example.com", "rp_id" => "fin.example.com")
    end

    it "lists the restore-critical secrets by fingerprint, never by value" do
      with_env("AR_ENCRYPTION_PRIMARY_KEY" => "primary-key-value") do
        get "/api/v1/backups", headers: headers
      end

      key = response.parsed_body["keys"].find { |k| k["name"] == "AR_ENCRYPTION_PRIMARY_KEY" }
      expect(key["fingerprint"]).to eq("sha256:#{Digest::SHA256.hexdigest("primary-key-value").first(12)}")
      expect(response.body).not_to include("primary-key-value")
    end

    it "reads a job whose worker died as failed rather than forever running" do
      travel_to(3.hours.ago) { stage("dead00", status: "running") }

      get "/api/v1/backups", headers: headers

      expect(response.parsed_body["backups"].sole).to include("status" => "failed")
    end
  end

  describe "POST /api/v1/backups" do
    it "starts a manual job that records who asked and from which address" do
      host! "fin.example.com"

      expect { post "/api/v1/backups", headers: headers }
        .to have_enqueued_job(ProduceBackupJob)

      expect(response).to have_http_status(:accepted)
      state = FogBackup::Staging.status(response.parsed_body["id"])
      expect(state).to include(
        "origin" => "manual", "requested_by" => Current.user.email,
        "host" => "fin.example.com", "rp_id" => "fin.example.com"
      )
    end

    it "returns the running manual job instead of stacking a second" do
      post "/api/v1/backups", headers: headers
      first = response.parsed_body["id"]

      expect { post "/api/v1/backups", headers: headers }.not_to have_enqueued_job(ProduceBackupJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(first)
    end

    it "409s while fog is producing its own backup" do
      stage("f09f09", status: "running", origin: "fog")
      post "/api/v1/backups", headers: headers
      expect(response).to have_http_status(:conflict)
    end
  end

  describe "downloading" do
    before { stage("aaa111") }

    it "hands the browser a ticketed URL that streams the artifact without a bearer header" do
      post "/api/v1/backups/aaa111/download", headers: headers
      expect(response).to have_http_status(:ok)

      get response.parsed_body["url"]

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("tar bytes")
      expect(response.headers["Content-Disposition"]).to include("fin-20260930-120000.fogpack.tar")
    end

    it "refuses the artifact without a ticket, with another backup's, and once it expires" do
      stage("bbb222")
      get "/api/v1/backups/aaa111/artifact"
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/backups/bbb222/download", headers: headers
      other = response.parsed_body["url"].split("ticket=").last
      get "/api/v1/backups/aaa111/artifact?ticket=#{other}"
      expect(response).to have_http_status(:not_found)

      post "/api/v1/backups/aaa111/download", headers: headers
      url = response.parsed_body["url"]
      travel_to(6.minutes.from_now) { get url }
      expect(response).to have_http_status(:unauthorized)
    end

    it "won't ticket a backup that isn't finished or one that is fog's" do
      stage("ccc333", status: "running")
      stage("f09f09", origin: "fog")

      %w[ccc333 f09f09].each do |id|
        post "/api/v1/backups/#{id}/download", headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /api/v1/backups/:id" do
    it "removes a finished backup" do
      stage("aaa111")
      delete "/api/v1/backups/aaa111", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(FogBackup::Staging.job_dir("aaa111")).not_to exist
    end

    it "leaves a backup that is still being produced, and any of fog's" do
      stage("ccc333", status: "running")
      delete "/api/v1/backups/ccc333", headers: headers
      expect(response).to have_http_status(:conflict)

      stage("f09f09", origin: "fog")
      delete "/api/v1/backups/f09f09", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(FogBackup::Staging.job_dir("f09f09")).to exist
    end
  end

  describe "POST /api/v1/backups/keys" do
    it "returns the fingerprinted secrets' values, uncached, and logs that it did" do
      with_env("AR_ENCRYPTION_PRIMARY_KEY" => "primary-key-value", "SECRET_KEY_BASE" => "skb-value") do
        post "/api/v1/backups/keys", headers: headers
      end

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      keys = response.parsed_body["keys"].index_by { |k| k["name"] }
      expect(keys["AR_ENCRYPTION_PRIMARY_KEY"]).to include(
        "value" => "primary-key-value",
        "fingerprint" => "sha256:#{Digest::SHA256.hexdigest("primary-key-value").first(12)}"
      )
      expect(keys["SECRET_KEY_BASE"]["value"]).to eq("skb-value")
      expect(ActivityEntry.where(event: "backup.keys.revealed")).to exist
    end
  end
end
