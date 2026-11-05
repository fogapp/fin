require "rails_helper"

RSpec.describe Workflows::Monitor do
  let(:broker)  { create(:broker) }
  let(:account) { create(:account, broker: broker, balance_usd: 1000) }

  let(:workflow) do
    create(:workflow, name: "Low balance", trigger_type: "monitor",
           trigger_config: {
             "subject"    => "account",
             "conditions" => [ { "field" => "balance_usd", "operator" => "less_than", "value" => "500" } ]
           })
  end

  let(:monitor) { described_class.new(workflow) }

  it "does not fire while the condition is false" do
    expect {
      expect(monitor.check(account)).to be_nil
    }.not_to change(WorkflowRun, :count)
    expect(WorkflowMonitorState.sole.result).to be(false)
  end

  it "fires exactly once on the false→true edge" do
    monitor.check(account) # establish false state
    account.update_columns(balance_usd: 100)

    run = nil
    expect {
      run = monitor.check(account)
    }.to change(WorkflowRun, :count).by(1)
      .and have_enqueued_job(Workflows::ExecuteRunJob)

    expect(run.event_type).to eq("monitor.triggered")
    expect(run.subject_id).to eq(account.id)

    # Still true → no re-fire
    expect { monitor.check(account) }.not_to change(WorkflowRun, :count)

    # Recovers, then dips again → fires again
    account.update_columns(balance_usd: 900)
    monitor.check(account)
    account.update_columns(balance_usd: 50)
    expect { monitor.check(account) }.to change(WorkflowRun, :count).by(1)
  end

  it "fires immediately when the very first evaluation is true" do
    account.update_columns(balance_usd: 100)
    expect { monitor.check(account) }.to change(WorkflowRun, :count).by(1)
  end

  it "writes the state row only when the result flips" do
    monitor.check(account) # creates the state (false)
    state = WorkflowMonitorState.sole

    expect { monitor.check(account) }
      .not_to change { state.reload.updated_at }

    account.update_columns(balance_usd: 100)
    expect { monitor.check(account) }
      .to change { state.reload.result }.from(false).to(true)
  end

  describe "#check_batch" do
    it "creates states for new subjects and fires rising edges with one state lookup" do
      low  = create(:account, broker: broker, name: "Low",  account_number: "L9", balance_usd: 10)
      high = create(:account, broker: broker, name: "High", account_number: "H9", balance_usd: 9000)

      expect {
        monitor.check_batch([ low, high ])
      }.to change(WorkflowRun, :count).by(1)

      expect(WorkflowMonitorState.where(subject_id: low.id).sole.result).to be(true)
      expect(WorkflowMonitorState.where(subject_id: high.id).sole.result).to be(false)

      # Re-sweep with unchanged results: no state writes.
      states = WorkflowMonitorState.order(:id).pluck(:updated_at)
      monitor.check_batch([ low, high ])
      expect(WorkflowMonitorState.order(:id).pluck(:updated_at)).to eq(states)
    end
  end

  describe "validation" do
    it "rejects monitors without a valid subject or conditions" do
      w = build(:workflow, trigger_type: "monitor", trigger_config: { "subject" => "weather" })
      expect(w).not_to be_valid
      expect(w.errors[:trigger_config].join).to match(/subject model/)
      expect(w.errors[:trigger_config].join).to match(/condition/)
    end
  end

  describe "event-driven evaluation" do
    it "re-checks monitors when a watched model record changes" do
      workflow # create the monitor
      Workflows::Events.reset_cache

      expect {
        account.update!(name: "Renamed")
      }.to have_enqueued_job(Workflows::EvaluateMonitorsJob)
        .with(Current.household.id.to_s, "Account", account.id.to_s)
    end

    it "evaluates and fires through the job" do
      workflow
      account.update_columns(balance_usd: 100)

      expect {
        Workflows::EvaluateMonitorsJob.perform_now(Current.household.id, "Account", account.id)
      }.to change(WorkflowRun, :count).by(1)
    end
  end

  describe "sweep" do
    it "evaluates every subject for every monitor across households" do
      workflow
      low  = create(:account, broker: broker, name: "Low", account_number: "L1", balance_usd: 10)
      high = create(:account, broker: broker, name: "High", account_number: "H1", balance_usd: 9000)

      expect {
        Workflows::MonitorSweepJob.perform_now
      }.to change(WorkflowRun, :count).by(1)

      expect(WorkflowRun.sole.subject_id).to eq(low.id)
      # The SQL-narrowed walk never instantiates non-matching subjects, so
      # they carry no state row — absence is the false baseline check() uses.
      expect(WorkflowMonitorState.where(subject_id: high.id)).to be_empty
    end
  end

  describe "#sweep!" do
    it "re-fires after a subject stops matching and matches again (falling edge reset set-wise)" do
      account.update_columns(balance_usd: 100)
      expect { monitor.sweep! }.to change(WorkflowRun, :count).by(1)

      # Stops matching: the narrowed walk skips it, but its stale true state
      # must flip so the next rise is an edge again.
      account.update_columns(balance_usd: 2000)
      expect { monitor.sweep! }.not_to change(WorkflowRun, :count)
      expect(WorkflowMonitorState.sole.result).to be(false)

      account.update_columns(balance_usd: 50)
      expect { monitor.sweep! }.to change(WorkflowRun, :count).by(1)
    end

    it "falls back to the full walk for conditions the SQL translator can't express" do
      account # materialize the non-matching subject before the sweep
      workflow.update!(trigger_config: {
        "subject"    => "account",
        "conditions" => [ { "field" => "name", "operator" => "matches", "value" => "Low" } ]
      })
      low = create(:account, broker: broker, name: "Low cash", account_number: "L2", balance_usd: 10)

      expect { monitor.sweep! }.to change(WorkflowRun, :count).by(1)
      expect(WorkflowRun.sole.subject_id).to eq(low.id)
      # Full walk evaluates (and records state for) non-matching rows too.
      expect(WorkflowMonitorState.where(subject_id: account.id).sole.result).to be(false)
    end
  end
end
