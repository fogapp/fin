# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/setup/restore", type: :request do
  after { FileUtils.rm_rf(FogBackup::Staging.root) }

  # household_context seeds a user before every example; restore is a
  # fresh-instance-only surface.
  def make_fresh!
    Current.reset
    HouseholdMembership.delete_all
    User.delete_all
  end

  def artifact_upload(contents)
    file = Tempfile.new([ "artifact", ".tar" ])
    file.write(contents)
    file.flush
    Rack::Test::UploadedFile.new(file.path, "application/x-tar")
  end

  it "refuses once any user exists" do
    post "/api/v1/setup/restore", params: { artifact: artifact_upload("x") }
    expect(response).to have_http_status(:forbidden)
  end

  it "requires an artifact upload" do
    make_fresh!
    post "/api/v1/setup/restore"
    expect(response).to have_http_status(:bad_request)
  end

  it "rejects an unreadable artifact with the preflight and leaves nothing armed" do
    make_fresh!
    expect(FogBackup::Restart).not_to receive(:schedule!)

    post "/api/v1/setup/restore", params: { artifact: artifact_upload("not a tar") }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["errors"]).to be_present
    expect(response.parsed_body).to have_key("preflight")
    expect(FogBackup::Staging).not_to be_armed
    expect(FogBackup::Staging.pending_artifact).not_to exist
  end

  it "arms restore-on-boot and schedules the restart when the preflight passes" do
    make_fresh!
    allow(FogBackup::Preflight).to receive(:check)
      .and_return(FogBackup::Preflight::Result.new(errors: [], warnings: [], manifest: nil))
    allow(FogBackup::Serializer).to receive(:preflight_json).and_return({ ok: true })
    expect(FogBackup::Restart).to receive(:schedule!)

    post "/api/v1/setup/restore", params: { artifact: artifact_upload("artifact bytes"), confirm_identity: "true" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("restarting" => true, "preflight" => { "ok" => true })
    expect(FogBackup::Staging).to be_armed
    expect(FogBackup::Staging.marker).to include("staged_by" => "setup-wizard", "confirm_identity" => true)
  end
end
