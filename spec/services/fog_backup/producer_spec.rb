# typed: false
# frozen_string_literal: true

require "rails_helper"

# Real pg_dump + real tar: the artifact this produces is the artifact fog
# downloads, so the round trip through Preflight is the contract's own test.
RSpec.describe FogBackup::Producer do
  after { FileUtils.rm_rf(FogBackup::Staging.root) }

  it "produces a verifiable artifact that passes preflight" do
    job_id = "testjob1"
    FogBackup::Staging.write_status(job_id, "running")

    message = described_class.new(job_id: job_id).call

    expect(message).to include("artifact")

    path = FogBackup::Staging.artifact_path(job_id)
    info = FogBackup::Staging.artifact_info(job_id)
    expect(path).to exist
    # The producer's claim must be independently verifiable — it's what fog
    # checks the download against.
    expect(path.size).to eq(info["bytes"])
    expect(Digest::SHA256.file(path.to_s).hexdigest).to eq(info["sha256"])

    result = FogBackup::Preflight.check(artifact_path: path)
    expect(result.errors).to eq([])
    expect(result.manifest.app).to eq("fin")
    expect(result.manifest.schema_version).to eq(FogBackup::Manifest.code_schema_version)
    expect(result.manifest.dump_tool).to match(/\Apg_dump \(PostgreSQL\) \d+/)
  end

  # fog-backup/2: nothing inside is compressed, so fog's deduplicating store
  # shares unchanged chunks between nights (it compresses what it keeps).
  it "produces fog-backup/2: an uncompressed custom-format dump and a plain storage tar" do
    FogBackup::Staging.write_status("v2job", "running")
    allow(FogBackup::Shell).to receive(:run).and_call_original

    described_class.new(job_id: "v2job").call

    expect(FogBackup::Shell).to have_received(:run)
      .with(array_including("pg_dump", "-Fc", "-Z0", "--no-owner", "--no-privileges", "--no-comments"), any_args)
    expect(FogBackup::Shell).not_to have_received(:run).with(array_including("--zstd"), any_args)

    artifact = FogBackup::Staging.artifact_path("v2job")
    result = FogBackup::Preflight.check(artifact_path: artifact)
    expect(result.errors).to eq([])
    expect(result.manifest.format).to eq("fog-backup/2")
    expect(result.manifest.components.map { |c| c["path"] }).to eq(%w[db/primary.dump files/storage.tar])

    Dir.mktmpdir do |dir|
      system("tar", "-xf", artifact.to_s, "-C", dir, exception: true)
      # A plain tar, not a zstd frame (magic 28 B5 2F FD).
      storage = Pathname(dir).join("files/storage.tar")
      expect(storage.binread(4).bytes).not_to eq([ 0x28, 0xB5, 0x2F, 0xFD ])
      expect(FogBackup::Shell.run([ "tar", "-tf", storage.to_s ]).success?).to be(true)
      # pg_restore reads the uncompressed dump unchanged.
      toc = FogBackup::Shell.run([ "pg_restore", "--list", Pathname(dir).join("db/primary.dump").to_s ])
      expect(toc.success?).to be(true)
      expect(toc.stdout).to match(/Compression: none/)
    end
  end

  # The artifact must say where its passkeys are bound, or a restore at
  # another address proceeds silently into a lock-out. An instance with no
  # configured RP ID only knows that from the request that asked.
  describe "identity" do
    def manifest_for(job_id)
      described_class.new(job_id: job_id).call
      FogBackup::Preflight.check(artifact_path: FogBackup::Staging.artifact_path(job_id), confirm_identity: true).manifest.raw
    end

    it "records the requesting host when no RP ID is configured" do
      FogBackup::Staging.write_status("ident1", "running", meta: { "host" => "fin.example.com", "rp_id" => "fin.example.com" })

      with_env("FIN_WEBAUTHN_RP_ID" => nil) do
        expect(manifest_for("ident1")["identity"]).to eq("host" => "fin.example.com", "webauthn_rp_id" => "fin.example.com")
      end
    end

    it "prefers the configured RP ID, and names it as the host when fog asked" do
      FogBackup::Staging.write_status("ident2", "running")

      with_env("FIN_WEBAUTHN_RP_ID" => "example.com") do
        expect(manifest_for("ident2")["identity"]).to eq("host" => "example.com", "webauthn_rp_id" => "example.com")
      end
    end

    it "keeps the job's origin through the producer's progress writes" do
      FogBackup::Staging.write_status("ident3", "running", meta: { "origin" => "manual", "requested_by" => "a@example.com" })

      described_class.new(job_id: "ident3").call

      expect(FogBackup::Staging.status("ident3")).to include("origin" => "manual", "requested_by" => "a@example.com")
    end
  end

  it "cleans its workdir on failure" do
    job_id = "testjob2"
    allow(FogBackup::Shell).to receive(:run)
      .and_return(FogBackup::Shell::Result.new(status: 1, stdout: "", stderr: "pg_dump: error"))

    expect { described_class.new(job_id: job_id).call }.to raise_error(FogBackup::Producer::Error, /pg_dump/)
    expect(FogBackup::Staging.backup_root.join("#{job_id}.tmp")).not_to exist
  end
end
