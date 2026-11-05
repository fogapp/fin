require "rails_helper"

RSpec.describe PruneActivityJob, type: :job do
  let(:broker)  { create(:broker) }
  let(:account) { create(:account, broker: broker) }

  def snapshot(recorded_at:)
    AccountBalanceSnapshot.create!(
      account: account, balance: 100, balance_currency: "USD",
      source: "manual", recorded_at: recorded_at
    )
  end

  it "prunes balance snapshots older than the 2-year retention" do
    old    = snapshot(recorded_at: 3.years.ago)
    recent = snapshot(recorded_at: 1.month.ago)

    described_class.perform_now

    expect(AccountBalanceSnapshot.exists?(old.id)).to    be false
    expect(AccountBalanceSnapshot.exists?(recent.id)).to be true
  end

  it "prunes routine activity entries after 90 days but keeps errors for a year" do
    routine = Activity.record(source: "test", event: "x.completed", summary: "old routine")
    error   = Activity.record(source: "test", event: "x.failed", severity: Severity::Error, summary: "old error")
    routine.update_column(:occurred_at, 120.days.ago)
    error.update_column(:occurred_at, 120.days.ago)

    described_class.perform_now

    expect(ActivityEntry.exists?(routine.id)).to be false
    expect(ActivityEntry.exists?(error.id)).to   be true
  end
end
