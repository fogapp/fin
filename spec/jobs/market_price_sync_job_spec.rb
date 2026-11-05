require "rails_helper"

RSpec.describe MarketPriceSyncJob, type: :job do
  it "runs the market data scheduler and records the outcome per household" do
    result = MarketData::Scheduler::Result.new(synced: 3, skipped: 1, failed: 0)
    scheduler = instance_double(MarketData::Scheduler, run: result)
    allow(MarketData::Scheduler).to receive(:new).and_return(scheduler)

    described_class.perform_now

    expect(scheduler).to have_received(:run)
    entry = ActivityEntry.where(source: "market_prices").sole
    expect(entry.summary).to match(/3 instruments/)
    expect(entry.payload).to include("synced" => 3, "skipped" => 1)
  end

  it "records a warning when instruments fail" do
    result = MarketData::Scheduler::Result.new(synced: 1, skipped: 0, failed: 2)
    allow(MarketData::Scheduler).to receive(:new)
      .and_return(instance_double(MarketData::Scheduler, run: result))

    described_class.perform_now

    expect(ActivityEntry.where(source: "market_prices").sole.severity).to eq(Severity::Warning)
  end
end
