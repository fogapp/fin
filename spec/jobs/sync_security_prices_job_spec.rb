require "rails_helper"

RSpec.describe SyncSecurityPricesJob, type: :job do
  let(:security) { create(:security, ticker: "AAPL", instrument_class: "equity") }
  let(:provider) { instance_double(MarketData::Providers::Tiingo, sync_candles: 3) }

  before do
    allow(Tiingo).to receive(:configured?).and_return(true)
    allow(MarketData::Providers::Tiingo).to receive(:new).and_return(provider)
  end

  def link
    InstrumentDataLink.find_by(security_id: security.id, capability: MarketData::Capability::Candles.serialize)
  end

  it "syncs candles through the router-pinned provider and records success" do
    described_class.perform_now(security.id)

    expect(provider).to have_received(:sync_candles).with(security, an_instance_of(InstrumentDataLink), full: true)
    expect(T.unsafe(link).provider).to eq(MarketData::Provider::Tiingo)
    expect(link.last_success_at).to be_present
    expect(security.reload.last_synced_at).to be_present
  end

  it "asks for the compact window once the instrument has candles" do
    create(:candle, security: security)

    described_class.perform_now(security.id)

    expect(provider).to have_received(:sync_candles).with(security, anything, full: false)
  end

  it "skips instruments no provider can price" do
    bond = create(:security, ticker: "UST30", instrument_class: "bond")

    described_class.perform_now(bond.id)

    expect(provider).not_to have_received(:sync_candles)
  end

  it "re-enqueues with a 60s wait when the provider is rate limited" do
    allow(provider).to receive(:sync_candles).and_raise(Tiingo::RateLimitError, "slow down")

    expect {
      described_class.perform_now(security.id)
    }.to have_enqueued_job(described_class).with(security.id).at(a_value_within(5.seconds).of(60.seconds.from_now))
    expect(link.consecutive_failures).to eq(0)
  end

  it "backs the link off on other failures without stamping last_synced_at" do
    allow(provider).to receive(:sync_candles).and_raise(Tiingo::Error, "bad ticker")

    expect { described_class.perform_now(security.id) }.not_to raise_error
    expect(link.consecutive_failures).to eq(1)
    expect(link.last_error).to eq("bad ticker")
    expect(security.reload.last_synced_at).to be_nil
  end
end
