require "swagger_helper"

RSpec.describe "Backups", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  after { FileUtils.rm_rf(FogBackup::Staging.root) }

  def stage_completed_backup(job_id = "abc123")
    FogBackup::Staging.write_status(job_id, "completed", meta: { "origin" => "manual", "requested_by" => "test@example.com" })
    FogBackup::Staging.artifact_path(job_id).write("tar bytes")
    FogBackup::Staging.artifact_info_path(job_id).write(
      { bytes: 9, sha256: "abc", created_at: Time.current.utc.iso8601 }.to_json
    )
    job_id
  end

  path "/api/v1/backups" do
    get "Manual backups staged on this instance, and what moving one needs" do
      tags "Backups"
      produces "application/json"

      response "200", "backup overview" do
        schema "$ref" => "#/components/schemas/BackupOverview"
        before { stage_completed_backup }
        run_test! do |response|
          expect(response.parsed_body["backups"].first).to include("id" => "abc123", "status" => "completed", "bytes" => 9)
        end
      end

      response "403", "caller is not a household admin" do
        schema "$ref" => "#/components/schemas/Error"
        let(:token) { create(:api_token, household: create(:household)) }
        run_test!
      end
    end

    post "Start producing a fog-backup/2 artifact" do
      tags "Backups"
      produces "application/json"

      response "202", "backup started" do
        schema "$ref" => "#/components/schemas/Backup"
        run_test!
      end

      response "409", "fog is producing a scheduled backup" do
        schema "$ref" => "#/components/schemas/Error"
        before { FogBackup::Staging.write_status("f09", "running", meta: { "origin" => "fog" }) }
        run_test!
      end
    end
  end

  path "/api/v1/backups/{id}" do
    parameter name: :id, in: :path, type: :string

    delete "Remove a staged backup artifact" do
      tags "Backups"

      response "204", "backup removed" do
        let(:id) { stage_completed_backup }
        run_test!
      end

      response "404", "no such backup" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { "dead" }
        run_test!
      end
    end
  end

  path "/api/v1/backups/{id}/download" do
    parameter name: :id, in: :path, type: :string

    post "Mint a short-lived download URL for a completed backup" do
      tags "Backups"
      produces "application/json"

      response "200", "download URL" do
        schema "$ref" => "#/components/schemas/BackupDownload"
        let(:id) { stage_completed_backup }
        run_test!
      end

      response "404", "no completed backup with that id" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { "dead" }
        run_test!
      end
    end
  end

  path "/api/v1/backups/{id}/artifact" do
    parameter name: :id, in: :path, type: :string
    parameter name: :ticket, in: :query, type: :string, required: true,
              description: "The ticket from POST /backups/{id}/download"

    get "Download a backup artifact with a download ticket" do
      tags "Backups"
      produces "application/x-tar"
      security []

      response "200", "the fog-backup/2 artifact" do
        let(:id)     { stage_completed_backup }
        let(:ticket) { Rails.application.message_verifier(:backup_download).generate({ "job" => id }, expires_in: 1.minute) }
        run_test! do |response|
          expect(response.body).to eq("tar bytes")
        end
      end

      response "401", "ticket missing or expired" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id)     { stage_completed_backup }
        let(:ticket) { "forged" }
        run_test!
      end
    end
  end

  path "/api/v1/backups/keys" do
    post "Reveal the secrets a restore of this instance's backups requires" do
      tags "Backups"
      produces "application/json"

      response "200", "instance keys" do
        schema "$ref" => "#/components/schemas/BackupKeys"
        run_test!
      end
    end
  end
end
