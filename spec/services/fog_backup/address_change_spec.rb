# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FogBackup::AddressChange do
  after { FileUtils.rm_rf(FogBackup::Staging.root) }

  def manifest(rp_id)
    FogBackup::Manifest::Parsed.new(raw: { "identity" => { "webauthn_rp_id" => rp_id } })
  end

  def write_receipt(extra = {})
    FogBackup::Staging.restore_root.mkpath
    FogBackup::Staging.receipt_path.write({ restored_at: Time.current.utc.iso8601 }.merge(extra).to_json)
  end

  describe ".detect" do
    it "names a move only when both addresses are known and differ" do
      expect(described_class.detect(manifest("old.example.com"), current_rp: "new.example.com"))
        .to have_attributes(from: "old.example.com", to: "new.example.com")
      expect(described_class.detect(manifest("Old.Example.com"), current_rp: "old.example.com")).to be_nil
      expect(described_class.detect(manifest(nil), current_rp: "new.example.com")).to be_nil
      expect(described_class.detect(manifest("old.example.com"), current_rp: nil)).to be_nil
    end
  end

  describe ".reconcile_pending!" do
    let(:household) { Current.household }
    let(:other)     { create(:household) }

    before { other }

    it "does nothing after a restore that stayed put" do
      write_receipt
      expect { described_class.reconcile_pending! }.not_to change { Issue.unscoped.count }
    end

    it "tells every restored household that its passkeys were left behind" do
      write_receipt(moved_from: "old.example.com", moved_to: "new.example.com")

      described_class.reconcile_pending!

      issues = Issue.unscoped.where(key: described_class::MOVED_KEY)
      expect(issues.pluck(:household_id)).to contain_exactly(household.id, other.id)
      expect(issues.first.title).to eq("Fin moved from old.example.com to new.example.com")
      expect(issues.first.body).to include("sign-in link")
    end

    it "flags Alchemy webhooks that still point at the old address, in that household only" do
      create(:alchemy_configuration, webhook_base_url: "https://old.example.com")
      write_receipt(moved_from: "old.example.com", moved_to: "new.example.com")

      described_class.reconcile_pending!

      flagged = Issue.unscoped.where(key: described_class::ALCHEMY_KEY)
      expect(flagged.pluck(:household_id)).to eq([ household.id ])
      expect(flagged.first.body).to include("https://old.example.com")
    end

    it "leaves webhooks alone when they already deliver somewhere else" do
      create(:alchemy_configuration, webhook_base_url: "https://tunnel.example.net")
      write_receipt(moved_from: "old.example.com", moved_to: "new.example.com")

      described_class.reconcile_pending!

      expect(Issue.unscoped.where(key: described_class::ALCHEMY_KEY)).not_to exist
    end

    it "runs once — a later restart doesn't reopen what was dismissed" do
      write_receipt(moved_from: "old.example.com", moved_to: "new.example.com")
      described_class.reconcile_pending!
      Issue.unscoped.update_all(dismissed_at: Time.current)

      described_class.reconcile_pending!

      expect(Issue.unscoped.where(dismissed_at: nil)).not_to exist
      expect(FogBackup::Staging.receipt["move_reconciled_at"]).to be_present
    end

    it "never raises into the boot it runs in" do
      write_receipt(moved_from: "old.example.com", moved_to: "new.example.com")
      allow(Issue).to receive(:raise_once!).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { described_class.reconcile_pending! }.not_to raise_error
    end
  end
end
