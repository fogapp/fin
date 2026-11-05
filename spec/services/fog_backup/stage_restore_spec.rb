# typed: false
# frozen_string_literal: true

require "rails_helper"

# The staging core shared by the setup wizard's restore and fog's
# POST /fog/restore. Preflight itself is covered on its own; here it's
# stubbed so each outcome (arm vs disarm) is exercised deterministically.
RSpec.describe FogBackup::StageRestore do
  after { FileUtils.rm_rf(FogBackup::Staging.root) }

  let(:ok)      { FogBackup::Preflight::Result.new(errors: [], warnings: [], manifest: nil) }
  let(:refused) { FogBackup::Preflight::Result.new(errors: [ "Artifact is for app \"other\"" ], warnings: [], manifest: nil) }

  def upload_with(contents)
    file = Tempfile.new([ "artifact", ".tar" ])
    file.write(contents)
    file.flush
    Struct.new(:tempfile).new(file)
  end

  it "moves an uploaded artifact into the staging path and arms restore-on-boot" do
    allow(FogBackup::Preflight).to receive(:check).and_return(ok)
    upload = upload_with("artifact bytes")

    result = described_class.call(upload: upload, staged: false, confirm: true, staged_by: "setup-wizard")

    expect(result).to be(ok)
    expect(FogBackup::Preflight).to have_received(:check)
      .with(artifact_path: FogBackup::Staging.pending_artifact, confirm_identity: true, rp_id: nil)
    expect(FogBackup::Staging.pending_artifact.read).to eq("artifact bytes")
    expect(FogBackup::Staging).to be_armed
    expect(FogBackup::Staging.marker).to include("staged_by" => "setup-wizard", "confirm_identity" => true)
  end

  it "judges identity against the staging request's host and carries it to restore-on-boot" do
    allow(FogBackup::Preflight).to receive(:check).and_return(ok)

    described_class.call(upload: upload_with("x"), staged: false, confirm: false,
                         staged_by: "setup-wizard", rp_id: "fin.example.com")

    expect(FogBackup::Preflight).to have_received(:check)
      .with(artifact_path: FogBackup::Staging.pending_artifact, confirm_identity: false, rp_id: "fin.example.com")
    expect(FogBackup::Staging.marker).to include("rp_id" => "fin.example.com")
  end

  it "uses an already-staged artifact in place when staged is true" do
    allow(FogBackup::Preflight).to receive(:check).and_return(ok)
    FogBackup::Staging.restore_root.mkpath
    FogBackup::Staging.pending_artifact.write("placed by fog")

    described_class.call(upload: nil, staged: true, confirm: false, staged_by: "fog-api")

    expect(FogBackup::Staging.pending_artifact.read).to eq("placed by fog")
    expect(FogBackup::Staging).to be_armed
  end

  it "disarms and leaves nothing staged when the preflight refuses" do
    allow(FogBackup::Preflight).to receive(:check).and_return(refused)
    upload = upload_with("wrong app")

    result = described_class.call(upload: upload, staged: false, confirm: false, staged_by: "fog-api")

    expect(result.ok?).to be(false)
    expect(FogBackup::Staging).not_to be_armed
    expect(FogBackup::Staging.pending_marker).not_to exist
    expect(FogBackup::Staging.pending_artifact).not_to exist
  end
end
