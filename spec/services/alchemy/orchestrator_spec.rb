require "rails_helper"

RSpec.describe Alchemy::Orchestrator do
  include ActiveJob::TestHelper

  let(:household)    { Current.household }
  let(:orchestrator) { described_class.new(household.id) }
  let(:config)       { AlchemyConfiguration.current.tap { |c| c.assign_attributes(api_key: "k") } }

  def enqueued = enqueued_jobs.map { |j| j["job_class"] }

  describe "#configuration_changed" do
    it "runs the first balance sync when a key is added for existing wallets" do
      create(:alchemy_wallet)
      clear_enqueued_jobs

      orchestrator.configuration_changed(config, was_configured: false, was_txn_enabled: false)

      expect(enqueued).to contain_exactly("AlchemySyncJob", "Alchemy::WebhookSyncJob")
    end

    it "starts transaction sync only when it is newly enabled" do
      config.transactions_enabled = true

      orchestrator.configuration_changed(config, was_configured: true, was_txn_enabled: false)
      expect(enqueued).to contain_exactly("Alchemy::TransactionSyncJob", "Alchemy::WebhookSyncJob")

      clear_enqueued_jobs
      orchestrator.configuration_changed(config, was_configured: true, was_txn_enabled: true)
      expect(enqueued).to eq([ "Alchemy::WebhookSyncJob" ])
    end

    it "enqueues nothing while unconfigured" do
      orchestrator.configuration_changed(AlchemyConfiguration.current, was_configured: false, was_txn_enabled: false)
      expect(enqueued).to be_empty
    end
  end

  describe "#wallet_added" do
    it "syncs balances, transactions and webhooks for the new wallet" do
      config.transactions_enabled = true
      orchestrator.wallet_added(config)
      expect(enqueued).to contain_exactly("AlchemySyncJob", "Alchemy::TransactionSyncJob", "Alchemy::WebhookSyncJob")
    end
  end

  describe "#wallet_changed" do
    it "only reconciles webhooks" do
      orchestrator.wallet_changed(config)
      expect(enqueued).to eq([ "Alchemy::WebhookSyncJob" ])
    end
  end
end
