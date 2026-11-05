require "rails_helper"

RSpec.describe CoinbaseSyncJob, type: :job do
  let(:result) { CoinbaseSyncer::Result.new(added: 2, skipped: 1, errors: []) }
  let(:syncer) { instance_double(CoinbaseSyncer, call: result) }

  before do
    CoinbaseConfiguration.create!(api_key_id: "k", api_key_secret: "s")
    allow(CoinbaseSyncer).to receive(:new).and_return(syncer)
  end

  it "sets Current.household to the supplied household for the syncer's duration" do
    captured = nil
    allow(syncer).to receive(:call) { captured = Current.household; result }

    described_class.perform_now(Current.household.id)
    expect(captured).to eq(Current.household)
  end

  it "logs added/skipped/error counts and each error" do
    errors = [ { account: "BTC", error: "boom" } ]
    allow(syncer).to receive(:call).and_return(
      CoinbaseSyncer::Result.new(added: 0, skipped: 0, errors: errors)
    )
    info_messages = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |orig, *args, &blk|
      info_messages << args.first
      orig.call(*args, &blk)
    end
    expect(Rails.logger).to receive(:warn).with(/account(=>|: )"BTC".*error(=>|: )"boom"/)

    described_class.perform_now(Current.household.id)

    expect(info_messages).to include(match(/added=0 skipped=0 errors=1/))
  end

  it "enqueues SyncCryptoPricesJob when CoinMarketCap is configured" do
    CoinMarketCapConfiguration.create!(api_key: "k")

    expect {
      described_class.perform_now(Current.household.id)
    }.to have_enqueued_job(SyncCryptoPricesJob).with(Current.household.id)
  end

  it "enqueues SyncCryptoPricesJob when the CoinMarketCap key exists only in ENV" do
    with_env("COINMARKETCAP_API_KEY" => "env-key") do
      expect {
        described_class.perform_now(Current.household.id)
      }.to have_enqueued_job(SyncCryptoPricesJob).with(Current.household.id)
    end
  end

  it "does not enqueue SyncCryptoPricesJob when CoinMarketCap is unconfigured" do
    with_env("COINMARKETCAP_API_KEY" => nil) do
      expect {
        described_class.perform_now(Current.household.id)
      }.not_to have_enqueued_job(SyncCryptoPricesJob)
    end
  end

  it "skips the sync without raising when Coinbase is not configured" do
    CoinbaseConfiguration.current.update!(api_key_id: nil, api_key_secret: nil)

    with_env("COINBASE_API_KEY_ID" => nil, "COINBASE_API_KEY_SECRET" => nil) do
      expect { described_class.perform_now(Current.household.id) }.not_to raise_error
    end
    expect(syncer).not_to have_received(:call)
  end

  it "syncs when the Coinbase credentials exist only in ENV" do
    CoinbaseConfiguration.current.update!(api_key_id: nil, api_key_secret: nil)

    with_env("COINBASE_API_KEY_ID" => "env-id", "COINBASE_API_KEY_SECRET" => "env-secret") do
      described_class.perform_now(Current.household.id)
    end
    expect(syncer).to have_received(:call)
  end
end
