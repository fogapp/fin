# typed: false
# frozen_string_literal: true

require "rails_helper"

# The format gate: this app writes fog-backup/2 and restores every format it
# ever wrote — fog-backup/1 artifacts, Manor's among them, included.
RSpec.describe FogBackup::Preflight, "format" do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  def check(**options) = described_class.check(artifact_path: build_fog_artifact(@dir, **options))

  it "accepts a fog-backup/2 artifact, its storage a plain tar" do
    result = check(format: "fog-backup/2")
    expect(result.errors).to eq([])
    expect(result.manifest.file_components.sole["path"]).to eq("files/storage.tar")
  end

  it "accepts a fog-backup/1 artifact, its storage a zstd tar" do
    result = check(format: "fog-backup/1")
    expect(result.errors).to eq([])
    expect(result.manifest.file_components.sole["path"]).to eq("files/storage.tar.zst")
  end

  it "accepts a fog-backup/1 artifact Manor made, before the rename" do
    result = check(format: "fog-backup/1", app: "manor")
    expect(result.errors).to eq([])
    expect(result.manifest.app).to eq("manor")
  end

  it "refuses a format it does not know" do
    expect(check(format: "fog-backup/3").errors.sole).to include("\"fog-backup/3\"", "fog-backup/1", "fog-backup/2")
    expect(check(format: "").errors.sole).to include("declares format")
  end

  it "refuses a file component it cannot unpack, before anything is staged" do
    expect(check(storage_path: "files/storage.zip").errors.sole).to include("files/storage.zip", ".tar")
  end
end
