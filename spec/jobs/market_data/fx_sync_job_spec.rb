require "rails_helper"

RSpec.describe MarketData::FxSyncJob, type: :job do
  let(:broker) { create(:broker) }
  let(:client) { instance_double(AlphaVantage::Client) }

  before do
    create(:account, broker: broker, balance_currency: "EUR")
    create(:account, broker: broker, balance_currency: "GBP")
    allow(AlphaVantage::Client).to receive(:new).and_return(client)
  end

  it "upserts a daily rate per non-USD currency" do
    allow(client).to receive(:fx_rate).with("EUR", "USD").and_return(BigDecimal("1.08"))
    allow(client).to receive(:fx_rate).with("GBP", "USD").and_return(BigDecimal("1.27"))

    described_class.perform_now

    expect(FxRate.where(date: Date.current).pluck(:base, :rate))
      .to contain_exactly([ "EUR", 1.08 ], [ "GBP", 1.27 ])
  end

  it "re-raises rate limits so the baseline retry runs the job again instead of logging success" do
    allow(client).to receive(:fx_rate).and_raise(AlphaVantage::RateLimitError, "throttled")

    # ApplicationJob's retry_on StandardError catches and re-enqueues.
    expect { described_class.perform_now }.to have_enqueued_job(described_class)
    expect(FxRate.count).to eq(0)
  end

  it "continues past a currency that fails with a non-rate-limit error" do
    allow(client).to receive(:fx_rate).with("EUR", "USD").and_raise(AlphaVantage::Error, "bad symbol")
    allow(client).to receive(:fx_rate).with("GBP", "USD").and_return(BigDecimal("1.27"))

    described_class.perform_now

    expect(FxRate.pluck(:base)).to eq([ "GBP" ])
  end
end
