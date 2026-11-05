require "rails_helper"

RSpec.describe "Alchemy transaction sync jobs" do
  let(:household) { Current.household }

  describe Alchemy::TransactionSyncTickJob do
    it "enqueues the household sync when transactions are enabled and due" do
      create(:alchemy_configuration, transactions_enabled: true, sync_frequency: "daily",
                                     transactions_last_synced_at: 25.hours.ago)

      expect { described_class.perform_now }
        .to have_enqueued_job(Alchemy::TransactionSyncJob).with(household.id)
    end

    it "skips households that are not yet due" do
      create(:alchemy_configuration, transactions_enabled: true, sync_frequency: "daily",
                                     transactions_last_synced_at: 1.hour.ago)

      expect { described_class.perform_now }.not_to have_enqueued_job(Alchemy::TransactionSyncJob)
    end

    it "fires immediately when never synced" do
      create(:alchemy_configuration, transactions_enabled: true, sync_frequency: "every_5_minutes")

      expect { described_class.perform_now }
        .to have_enqueued_job(Alchemy::TransactionSyncJob)
    end

    it "skips households with transactions disabled" do
      create(:alchemy_configuration, transactions_enabled: false)

      expect { described_class.perform_now }.not_to have_enqueued_job(Alchemy::TransactionSyncJob)
    end

    it "treats realtime as an hourly safety poll" do
      config = create(:alchemy_configuration, transactions_enabled: true, sync_frequency: "realtime",
                                              transactions_last_synced_at: 30.minutes.ago)
      expect(config.poll_due?).to be(false)

      config.update!(transactions_last_synced_at: 2.hours.ago)
      expect(config.poll_due?).to be(true)
    end
  end

  describe Alchemy::TransactionSyncJob do
    let(:syncer) { instance_double(Alchemy::TransactionSyncer) }

    def result(new_transfers:)
      Alchemy::TransactionSyncer::Result.new(pairs: 1, new_transfers: new_transfers,
                                             errors: [], touched_pairs: Set.new)
    end

    before do
      create(:alchemy_configuration, transactions_enabled: true)
      allow(Alchemy::TransactionSyncer).to receive(:new).and_return(syncer)
    end

    it "stamps the poll clock and chains a balance sync when transfers arrived" do
      allow(syncer).to receive(:call).and_return(result(new_transfers: 3))

      expect { described_class.perform_now(household.id) }
        .to have_enqueued_job(AlchemySyncJob).with(household.id)
      expect(AlchemyConfiguration.current.transactions_last_synced_at).to be_within(5.seconds).of(Time.current)
    end

    it "does not chain a balance sync when nothing new arrived" do
      allow(syncer).to receive(:call).and_return(result(new_transfers: 0))

      expect { described_class.perform_now(household.id) }
        .not_to have_enqueued_job(AlchemySyncJob)
    end

    it "narrows to the hinted wallets" do
      wallet = create(:alchemy_wallet)
      create(:alchemy_wallet) # other wallet, not hinted
      captured = nil
      allow(syncer).to receive(:call) { |wallets:| captured = wallets.to_a; result(new_transfers: 0) }

      described_class.perform_now(household.id, wallet_ids: [ wallet.id ])
      expect(captured).to eq([ wallet ])
    end

    it "is a no-op when transactions are not enabled" do
      AlchemyConfiguration.current.update!(transactions_enabled: false)
      expect(syncer).not_to receive(:call)

      described_class.perform_now(household.id)
    end
  end
end
