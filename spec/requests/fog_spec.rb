# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "fog-backup surface", type: :request do
  let(:token) { "fog-test-token" }

  around do |example|
    previous = ENV["FOG_API_TOKEN"]
    ENV["FOG_API_TOKEN"] = token
    example.run
  ensure
    ENV["FOG_API_TOKEN"] = previous
    FileUtils.rm_rf(FogBackup::Staging.root)
  end

  def fog_headers = { "Authorization" => "Bearer #{token}" }

  def json = JSON.parse(response.body)

  describe "auth" do
    it "rejects a missing bearer" do
      get "/fog/backup"
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a wrong bearer" do
      get "/fog/backup", headers: { "Authorization" => "Bearer nope" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses everything when no token is configured" do
      ENV.delete("FOG_API_TOKEN")
      get "/fog/backup", headers: fog_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # The household_context support creates a user before every example, so
  # "fresh" requires explicitly clearing them.
  def make_fresh!
    Current.reset
    HouseholdMembership.delete_all
    User.delete_all
  end

  describe "GET /fog/backup (descriptor)" do
    it "describes the instance" do
      get "/fog/backup", headers: fog_headers

      expect(response).to have_http_status(:ok)
      expect(json["contract"]).to eq("fog-backup/2")
      expect(json["app"]).to eq("fin")
      expect(json["fresh"]).to be(false) # household_context seeded a user
      expect(json["components"].map { |c| c["name"] }).to contain_exactly("primary", "storage")
      expect(json["version"]["schema_version"].to_i).to be > 0
    end

    it "reports fresh on an instance with no users" do
      make_fresh!
      get "/fog/backup", headers: fog_headers
      expect(json["fresh"]).to be(true)
    end
  end

  describe "POST /fog/backup" do
    it "starts a producer job and 409s while it runs, reporting the same job" do
      post "/fog/backup", headers: fog_headers
      expect(response).to have_http_status(:accepted)
      first_job = json["job"]
      expect(first_job).to be_present

      post "/fog/backup", headers: fog_headers
      expect(response).to have_http_status(:conflict)
      expect(json["job"]).to eq(first_job)
      expect(FogBackup::Staging.status(first_job)).to include("origin" => "fog")
    end
  end

  describe "GET /fog/backup/jobs/:id" do
    it "404s an unknown id" do
      get "/fog/backup/jobs/deadbeef", headers: fog_headers
      expect(response).to have_http_status(:not_found)
    end

    it "maps file-based state onto the contract vocabulary" do
      FogBackup::Staging.write_status("abc123", "running", progress: "dumping database")
      get "/fog/backup/jobs/abc123", headers: fog_headers
      expect(json).to eq("status" => "running", "progress" => "dumping database")

      FogBackup::Staging.write_status("abc123", "failed", error: "pg_dump exited 1")
      get "/fog/backup/jobs/abc123", headers: fog_headers
      expect(json["status"]).to eq("failed")
      expect(json["error"]).to eq("pg_dump exited 1")
    end

    it "reports a completed artifact with the producer's claim" do
      FogBackup::Staging.write_status("abc123", "completed")
      FogBackup::Staging.artifact_path("abc123").write("tar bytes")
      FogBackup::Staging.artifact_info_path("abc123").write({ bytes: 9, sha256: "abc" }.to_json)

      get "/fog/backup/jobs/abc123", headers: fog_headers
      expect(json["status"]).to eq("completed")
      expect(json["artifact"]).to eq("bytes" => 9, "sha256" => "abc")
    end
  end

  describe "artifact download and cleanup" do
    before do
      FogBackup::Staging.write_status("abc123", "completed")
      FogBackup::Staging.artifact_path("abc123").write("tar bytes")
      FogBackup::Staging.artifact_info_path("abc123").write({ bytes: 9, sha256: "abc" }.to_json)
    end

    it "streams the artifact" do
      get "/fog/backup/jobs/abc123/artifact", headers: fog_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("tar bytes")
    end

    it "removes staging on DELETE" do
      delete "/fog/backup/jobs/abc123", headers: fog_headers

      expect(response).to have_http_status(:no_content)
      expect(FogBackup::Staging.job_dir("abc123")).not_to exist
    end

    # Fog adopts a job a person started from Settings → Backup when its own
    # schedule fires mid-run; the person's download must outlive fog's tidy-up.
    it "answers DELETE but keeps an artifact that was requested manually" do
      FogBackup::Staging.write_status("abc123", "completed", meta: { "origin" => "manual" })

      delete "/fog/backup/jobs/abc123", headers: fog_headers

      expect(response).to have_http_status(:no_content)
      expect(FogBackup::Staging.artifact_path("abc123")).to exist
    end
  end

  describe "POST /fog/restore" do
    it "refuses when the instance already has data" do
      # household_context's seeded user is the "data".
      post "/fog/restore", headers: fog_headers, params: { staged: true }
      expect(response).to have_http_status(:conflict)
    end

    it "rejects an unreadable staged artifact and disarms" do
      make_fresh!
      FogBackup::Staging.restore_root.mkpath
      FogBackup::Staging.pending_artifact.write("not a tar")

      post "/fog/restore", headers: fog_headers, params: { staged: true }

      expect(response).to have_http_status(:unprocessable_content)
      expect(FogBackup::Staging.pending_artifact).not_to exist
    end
  end
end
