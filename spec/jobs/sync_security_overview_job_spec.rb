require "rails_helper"

# Trigger Zeitwerk autoload of app/services/alpha_vantage/client.rb so the
# inner error constants are defined even when we stub the syncer.
AlphaVantage::Client

RSpec.describe SyncSecurityOverviewJob, type: :job do
  let(:syncer) { instance_double(SecurityOverviewSyncer, call: true) }

  before { allow(SecurityOverviewSyncer).to receive(:new).and_return(syncer) }

  it "calls SecurityOverviewSyncer for a non-crypto security" do
    sec = create(:security, ticker: "AAPL", security_type: "Common Stock")
    described_class.perform_now(sec.id)
    expect(SecurityOverviewSyncer).to have_received(:new).with(sec)
    expect(syncer).to have_received(:call)
  end

  it "skips crypto securities without calling the syncer" do
    sec = create(:security, ticker: "BTC", security_type: "Crypto")
    described_class.perform_now(sec.id)
    expect(SecurityOverviewSyncer).not_to have_received(:new)
  end

  it "warns and returns when AlphaVantage::MissingKeyError is raised" do
    sec = create(:security, ticker: "AAPL")
    allow(syncer).to receive(:call).and_raise(AlphaVantage::MissingKeyError, "no key")

    expect(Rails.logger).to receive(:warn).with(/skipping #{sec.id}: no key/)
    expect { described_class.perform_now(sec.id) }.not_to raise_error
  end

  it "re-enqueues with a 60s wait when rate-limited" do
    sec = create(:security, ticker: "AAPL")
    allow(syncer).to receive(:call).and_raise(AlphaVantage::RateLimitError, "rate limit")

    expect {
      described_class.perform_now(sec.id)
    }.to have_enqueued_job(described_class).with(sec.id).at(a_value_within(5.seconds).of(60.seconds.from_now))
  end

  it "logs an error and returns on generic AlphaVantage::Error" do
    sec = create(:security, ticker: "AAPL")
    allow(syncer).to receive(:call).and_raise(AlphaVantage::Error, "boom")

    expect(Rails.logger).to receive(:error).with(/#{sec.id} failed: boom/)
    expect { described_class.perform_now(sec.id) }.not_to raise_error
  end
end
