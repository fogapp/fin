require "rails_helper"

RSpec.describe SyncCryptoPricesJob, type: :job do
  let(:result) { CoinMarketCap::Syncer::Result.new(updated: 2, skipped: 1, errors: []) }
  let(:syncer) { instance_double(CoinMarketCap::Syncer, call: result) }

  before do
    allow(CoinMarketCap::Syncer).to receive(:new).and_return(syncer)
    # The job iterates households and only syncs configured ones.
    config = CoinMarketCapConfiguration.unscoped.find_or_initialize_by(household: Current.household)
    config.update!(api_key: "test-key")
  end

  it "invokes CoinMarketCap::Syncer and logs the result counts" do
    info_messages = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |orig, *args, &blk|
      info_messages << args.first
      orig.call(*args, &blk)
    end

    described_class.perform_now

    expect(syncer).to have_received(:call)
    expect(info_messages).to include(match(/updated=2 skipped=1 errors=0/))
  end

  it "logs each error returned by the syncer" do
    errors = [
      { account: "BTC Wallet", error: "rate limit" },
      { account: "ETH Wallet", error: "no price" }
    ]
    allow(syncer).to receive(:call).and_return(
      CoinMarketCap::Syncer::Result.new(updated: 0, skipped: 0, errors: errors)
    )

    expect(Rails.logger).to receive(:error).with(/BTC Wallet: rate limit/)
    expect(Rails.logger).to receive(:error).with(/ETH Wallet: no price/)
    allow(Rails.logger).to receive(:info).and_call_original

    described_class.perform_now
  end

  it "is enqueueable on the market_data queue (declared in config/queue.yml)" do
    expect { described_class.perform_later }
      .to have_enqueued_job(described_class).on_queue("market_data")
  end

  it "continues past a household whose sync fails, recording an error activity" do
    other = create(:household, name: "Second Household")
    Current.set(household: other) do
      CoinMarketCapConfiguration.unscoped
        .find_or_initialize_by(household: other)
        .update!(api_key: "other-key")
    end

    calls = 0
    allow(syncer).to receive(:call) do
      calls += 1
      raise "config exploded" if calls == 1
      result
    end
    allow(Rails.logger).to receive(:error).and_call_original

    expect { described_class.perform_now }.not_to raise_error

    expect(calls).to eq(2) # the second household still synced
    failures = ActivityEntry.unscoped.where(source: "crypto_prices", event: "sync.failed")
    expect(failures.count).to eq(1)
    expect(failures.sole.severity).to eq(Severity::Error)
  end

  it "retries the whole job with backoff on a CoinMarketCap rate limit" do
    allow(syncer).to receive(:call).and_raise(CoinMarketCap::RateLimitError, "429")

    expect { described_class.perform_now }
      .to have_enqueued_job(described_class)
    expect(ActivityEntry.where(source: "crypto_prices", event: "sync.failed")).to be_empty
  end

  it "syncs a household whose CoinMarketCap key exists only in ENV" do
    CoinMarketCapConfiguration.delete_all

    with_env("COINMARKETCAP_API_KEY" => "env-key") { described_class.perform_now }

    expect(syncer).to have_received(:call)
  end

  it "skips households without any CoinMarketCap key" do
    CoinMarketCapConfiguration.delete_all

    with_env("COINMARKETCAP_API_KEY" => nil) { described_class.perform_now }

    expect(syncer).not_to have_received(:call)
  end

  it "re-prices only the given household when passed an id" do
    other = create(:household, name: "Second Household")
    CoinMarketCapConfiguration.unscoped.create!(household: other, api_key: "other-key")

    synced = []
    allow(syncer).to receive(:call) { synced << Current.household.id; result }

    described_class.perform_now(other.id)

    expect(synced).to eq([ other.id ])
  end
end
