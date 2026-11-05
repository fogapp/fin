require "rails_helper"

RSpec.describe AlchemySyncJob, type: :job do
  let(:result) { AlchemySyncer::Result.new(wallets: 2, positions: 5, skipped: 0, errors: []) }
  let(:syncer) { instance_double(AlchemySyncer, call: result) }

  before do
    AlchemyConfiguration.create!(api_key: "k")
    allow(AlchemySyncer).to receive(:new).and_return(syncer)
  end

  it "sets Current.household to the supplied household for the syncer's duration" do
    captured = nil
    allow(syncer).to receive(:call) { captured = Current.household; result }

    described_class.perform_now(Current.household.id)
    expect(captured).to eq(Current.household)
  end

  it "logs wallets/positions/error counts and each error" do
    errors = [ { wallet: "0xabc", error: "boom" } ]
    allow(syncer).to receive(:call).and_return(
      AlchemySyncer::Result.new(wallets: 1, positions: 0, skipped: 0, errors: errors)
    )
    info_messages = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |orig, *args, &blk|
      info_messages << args.first
      orig.call(*args, &blk)
    end
    expect(Rails.logger).to receive(:warn).with(/wallet(=>|: )"0xabc".*error(=>|: )"boom"/)

    described_class.perform_now(Current.household.id)

    expect(info_messages).to include(match(/wallets=1 positions=0 errors=1/))
  end

  it "publishes alchemy.sync_completed with the sync result" do
    expect(Workflows::Events).to receive(:publish).with(
      "alchemy.sync_completed",
      subject: Current.household,
      payload: { "wallets" => 2, "positions" => 5, "errors" => 0 }
    )

    described_class.perform_now(Current.household.id)
  end

  it "runs the gas drift sweep when transactions syncing is configured" do
    AlchemyConfiguration.current.update!(transactions_enabled: true)
    sweep = instance_double(Alchemy::GasDriftSweep, call: Alchemy::GasDriftSweep::Result.new(swept: 3, skipped: 1))
    allow(Alchemy::GasDriftSweep).to receive(:new).and_return(sweep)

    described_class.perform_now(Current.household.id)

    expect(sweep).to have_received(:call)
  end

  it "does not run the gas drift sweep when transactions syncing is not configured" do
    expect(Alchemy::GasDriftSweep).not_to receive(:new)

    described_class.perform_now(Current.household.id)
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

  it "skips the sync without raising when Alchemy is not configured" do
    AlchemyConfiguration.current.update!(api_key: nil)

    expect { described_class.perform_now(Current.household.id) }.not_to raise_error
    expect(syncer).not_to have_received(:call)
  end
end
