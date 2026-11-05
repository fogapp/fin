# typed: false
# frozen_string_literal: true

require "rails_helper"

# The identity gate: an artifact whose passkeys are bound to another address
# restores only as a confirmed decision — and a same-address restore never
# asks, whether the address comes from the environment or from the request.
RSpec.describe FogBackup::Preflight, "identity" do
  after { FileUtils.rm_rf(FogBackup::Staging.root) }

  let(:artifact) do
    FogBackup::Staging.write_status("pf1", "running", meta: { "host" => "old.example.com", "rp_id" => "old.example.com" })
    with_env("FIN_WEBAUTHN_RP_ID" => nil) { FogBackup::Producer.new(job_id: "pf1").call }
    FogBackup::Staging.artifact_path("pf1")
  end

  def check(**options)
    described_class.check(artifact_path: artifact, **options)
  end

  it "passes at the same address, configured or derived from the staging request" do
    with_env("FIN_WEBAUTHN_RP_ID" => "old.example.com") { expect(check.errors).to eq([]) }
    with_env("FIN_WEBAUTHN_RP_ID" => nil) { expect(check(rp_id: "old.example.com").errors).to eq([]) }
  end

  it "refuses another address until the move is confirmed" do
    with_env("FIN_WEBAUTHN_RP_ID" => "new.example.com") do
      refused = check
      expect(refused.errors.sole).to include("old.example.com", "new.example.com", "confirm_identity")

      confirmed = check(confirm_identity: true)
      expect(confirmed.errors).to eq([])
      expect(confirmed.warnings.sole).to include("sign-in link")
    end
  end

  it "takes an artifact made before the rename from Manor as its own" do
    stub_const("FogBackup::Manifest::APP", "manor")
    legacy = artifact
    stub_const("FogBackup::Manifest::APP", "fin")

    with_env("FIN_WEBAUTHN_RP_ID" => "old.example.com") do
      result = described_class.check(artifact_path: legacy)
      expect(result.manifest.app).to eq("manor")
      expect(result.errors).to eq([])
    end
  end

  it "refuses another app's artifact" do
    stub_const("FogBackup::Manifest::APP", "office")
    other = artifact
    stub_const("FogBackup::Manifest::APP", "fin")

    with_env("FIN_WEBAUTHN_RP_ID" => "old.example.com") do
      expect(described_class.check(artifact_path: other).errors).to include(a_string_including("for app \"office\""))
    end
  end

  it "lets the configured RP ID outrank the request's host" do
    with_env("FIN_WEBAUTHN_RP_ID" => "new.example.com") do
      expect(check(rp_id: "old.example.com").errors).not_to be_empty
    end
  end
end
