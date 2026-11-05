require "rails_helper"

RSpec.describe Activity do
  it "records an entry with the current trace id" do
    Current.trace_id = "11111111-1111-1111-1111-111111111111"
    account = create(:account)

    entry = described_class.record(
      source: "plaid_sync", event: "sync.completed",
      summary: "Plaid sync: 3 added", subject: account,
      payload: { added: 3 }, duration_ms: 1234.7
    )

    expect(entry.household_id).to eq(Current.household.id)
    expect(entry.trace_id).to eq("11111111-1111-1111-1111-111111111111")
    expect(entry.subject).to eq(account)
    expect(entry.payload).to eq("added" => 3)
    expect(entry.duration_ms).to eq(1235)
  end

  it "never raises out of the observed operation" do
    allow(ActivityEntry).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")

    expect {
      expect(described_class.record(source: "x", event: "y", summary: "z")).to be_nil
    }.not_to raise_error
  end

  it "skips recording when no household can be resolved" do
    Current.reset
    expect(described_class.record(source: "x", event: "y", summary: "z")).to be_nil
  end

  it "publishes system.error_recorded for error entries from non-workflow sources" do
    create(:workflow, name: "Alert me", trigger_type: "system.error_recorded")
    Workflows::Events.reset_cache

    expect {
      described_class.record(source: "plaid_sync", event: "sync.failed",
                             severity: Severity::Error, summary: "Plaid down")
    }.to have_enqueued_job(Workflows::DispatchJob).with { |type, *|
      expect(type).to eq("system.error_recorded")
    }
  end

  it "does not re-publish workflow-sourced errors (loop guard)" do
    create(:workflow, name: "Alert me", trigger_type: "system.error_recorded")
    Workflows::Events.reset_cache

    expect {
      described_class.record(source: "workflow", event: "run.failed",
                             severity: Severity::Error, summary: "run died")
    }.not_to have_enqueued_job(Workflows::DispatchJob)
  end
end
