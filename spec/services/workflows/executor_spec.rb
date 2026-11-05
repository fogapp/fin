require "rails_helper"

RSpec.describe Workflows::Executor do
  let(:account)  { create(:account) }
  let(:workflow) { create(:workflow, trigger_type: "cash_transaction.created") }

  def run_for(subject, workflow: self.workflow, triggered_by: nil)
    create(:workflow_run,
           workflow: workflow,
           subject_type: subject.class.name, subject_id: subject.id,
           event_type: workflow.trigger_type,
           triggered_by_run: triggered_by)
  end

  def execute(run, resume_from: nil)
    described_class.new(run).call(resume_from_step_id: resume_from)
    run.reload
  end

  describe "branch semantics" do
    it "runs the first matching branch's children and records the rest" do
      txn = create(:cash_transaction, :bank, account: account, description: "STARBUCKS #9")
      workflow.replace_steps!([
        { kind: "branch",
          config: { match_all: true,
                    conditions: [ { field: "description", operator: "contains", value: "WALMART" } ] },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "walmart!" } } } ] },
        { kind: "branch",
          config: { match_all: true,
                    conditions: [ { field: "description", operator: "contains", value: "STARBUCKS" } ] },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "coffee" } } } ] },
        { kind: "branch", config: { else: true },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "other" } } } ] }
      ])

      run = execute(run_for(txn))

      expect(run.status).to eq(WorkflowRun::Status::Completed)
      expect(txn.reload.memo).to eq("coffee")
      statuses = run.run_steps.includes(:workflow_step).map { |rs| [ rs.workflow_step&.kind, rs.status ] }
      expect(statuses).to include(
        [ WorkflowStep::Kind::Branch, WorkflowRunStep::Status::NotMatched ],
        [ WorkflowStep::Kind::Branch, WorkflowRunStep::Status::Matched ],
        [ WorkflowStep::Kind::Branch, WorkflowRunStep::Status::Skipped ]
      )
    end

    it "takes the else branch when nothing matches" do
      txn = create(:cash_transaction, :bank, account: account, description: "GAS STATION")
      workflow.replace_steps!([
        { kind: "branch",
          config: { conditions: [ { field: "description", operator: "contains", value: "STARBUCKS" } ] },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "coffee" } } } ] },
        { kind: "branch", config: { else: true },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "fallback" } } } ] }
      ])

      execute(run_for(txn))
      expect(txn.reload.memo).to eq("fallback")
    end

    it "supports match_any branches" do
      txn = create(:cash_transaction, :bank, account: account, description: "SHELL 42")
      workflow.replace_steps!([
        { kind: "branch",
          config: { match_all: false,
                    conditions: [
                      { field: "description", operator: "contains", value: "CHEVRON" },
                      { field: "description", operator: "contains", value: "SHELL" }
                    ] },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "fuel" } } } ] }
      ])

      execute(run_for(txn))
      expect(txn.reload.memo).to eq("fuel")
    end

    it "never evaluates fields outside the catalog whitelist" do
      txn = create(:cash_transaction, :bank, account: account, description: "X")
      workflow.replace_steps!([
        { kind: "branch",
          config: { conditions: [ { field: "destroy", operator: "present", value: "" } ] },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "boom" } } } ] }
      ])

      run = execute(run_for(txn))

      expect(run.status).to eq(WorkflowRun::Status::Completed)
      expect(txn.reload.memo).to be_nil
      expect(CashTransaction.exists?(txn.id)).to be(true)
    end
  end

  describe "data actions" do
    it "applies assignments through the rules engine action classes" do
      merchant = create(:merchant)
      txn = create(:cash_transaction, :bank, account: account, description: "ANY")
      workflow.replace_steps!([
        { kind: "action", config: { action_type: "assign_merchant", params: { merchant_id: merchant.id } } }
      ])

      run = execute(run_for(txn))

      expect(txn.reload.merchant_id).to eq(merchant.id)
      expect(run.run_steps.last.status).to eq(WorkflowRunStep::Status::Applied)
    end

    it "records unknown action types as errors without failing the run" do
      txn = create(:cash_transaction, :bank, account: account)
      workflow.replace_steps!([
        { kind: "action", config: { action_type: "launch_rocket", params: {} } }
      ])

      run = execute(run_for(txn))

      expect(run.status).to eq(WorkflowRun::Status::Completed)
      expect(run.run_steps.last.status).to eq(WorkflowRunStep::Status::Error)
      expect(run.run_steps.last.output["error"]).to match(/Unknown action/)
    end
  end

  describe "wait steps" do
    it "parks the run, schedules a resume, and executes children on resume" do
      txn = create(:cash_transaction, :bank, account: account, description: "ATM WITHDRAWAL")
      workflow.replace_steps!([
        { kind: "action", config: { action_type: "set_memo", params: { value: "seen" } } },
        { kind: "wait", config: { duration_seconds: 3600 },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "after wait" } } } ] }
      ])

      run = nil
      expect {
        run = execute(run_for(txn))
      }.to have_enqueued_job(Workflows::ExecuteRunJob)

      expect(run.status).to eq(WorkflowRun::Status::Waiting)
      expect(txn.reload.memo).to eq("seen")
      wait_record = run.run_steps.find { |rs| rs.status == WorkflowRunStep::Status::Waiting }
      expect(wait_record.resume_at).to be_within(5.seconds).of(1.hour.from_now)

      execute(run, resume_from: run.cursor_step_id)
      expect(run.reload.status).to eq(WorkflowRun::Status::Completed)
      expect(txn.reload.memo).to eq("after wait")
    end

    it "cancels a waiting run whose subject was deleted before resume" do
      txn = create(:cash_transaction, :bank, account: account)
      workflow.replace_steps!([
        { kind: "wait", config: { duration_seconds: 60 },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "x" } } } ] }
      ])

      run = execute(run_for(txn))
      expect(run.status).to eq(WorkflowRun::Status::Waiting)

      txn.destroy!
      execute(run, resume_from: run.cursor_step_id)
      expect(run.reload.status).to eq(WorkflowRun::Status::Cancelled)
    end
  end

  describe "chain protection" do
    it "cancels when the same workflow appears in the run ancestry" do
      txn = create(:cash_transaction, :bank, account: account)
      parent = run_for(txn)
      child  = run_for(txn, triggered_by: parent)

      execute(child)
      expect(child.reload.status).to eq(WorkflowRun::Status::Cancelled)
      expect(child.error).to match(/cycle/)
    end

    it "cancels when the chain exceeds the depth cap" do
      txn = create(:cash_transaction, :bank, account: account)
      chain = create(:workflow_run, workflow: create(:workflow, name: "w0"),
                     subject_type: "CashTransaction", subject_id: txn.id, event_type: "x.created")
      described_class::MAX_CHAIN_DEPTH.times do |i|
        chain = create(:workflow_run, workflow: create(:workflow, name: "w#{i + 1}"),
                       subject_type: "CashTransaction", subject_id: txn.id,
                       event_type: "x.created", triggered_by_run: chain)
      end

      run = run_for(txn, triggered_by: chain)
      execute(run)
      expect(run.reload.status).to eq(WorkflowRun::Status::Cancelled)
      expect(run.error).to match(/depth/)
    end
  end

  describe "log levels" do
    let(:txn) { create(:cash_transaction, :bank, account: account, description: "GAS STATION") }

    def noop_steps!
      workflow.replace_steps!([
        { kind: "branch",
          config: { conditions: [ { field: "description", operator: "contains", value: "STARBUCKS" } ] },
          children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "coffee" } } } ] }
      ])
    end

    def memo_steps!
      workflow.replace_steps!([
        { kind: "action", config: { action_type: "set_memo", params: { value: "x" } } }
      ])
    end

    it "keeps no-match runs at info but writes no activity entry" do
      noop_steps!
      run = execute(run_for(txn))
      expect(run.status).to eq(WorkflowRun::Status::Completed)
      expect(ActivityEntry.where(caused_by: run)).to be_empty
    end

    it "writes an activity entry at info when a run applies an action" do
      memo_steps!
      run = execute(run_for(txn))
      expect(ActivityEntry.where(caused_by: run).count).to eq(1)
    end

    it "writes an activity entry for every run at debug" do
      Current.household.update!(workflow_log_level: Workflows::LogLevel::Debug)
      noop_steps!
      run = execute(run_for(txn))
      expect(ActivityEntry.where(caused_by: run).count).to eq(1)
    end

    it "discards no-effect runs entirely at none" do
      Current.household.update!(workflow_log_level: Workflows::LogLevel::None)
      noop_steps!
      run = run_for(txn)
      described_class.new(run).call
      expect(WorkflowRun.exists?(run.id)).to be(false)
      expect(ActivityEntry.where(source: "workflow").count).to eq(0)
    end

    it "keeps runs that applied actions at none, without a completion entry" do
      Current.household.update!(workflow_log_level: Workflows::LogLevel::None)
      memo_steps!
      run = execute(run_for(txn))
      expect(run.status).to eq(WorkflowRun::Status::Completed)
      expect(txn.reload.memo).to eq("x")
      expect(ActivityEntry.where(caused_by: run)).to be_empty
    end

    it "still records failed runs at none" do
      Current.household.update!(workflow_log_level: Workflows::LogLevel::None)
      memo_steps!
      allow(Workflows::Actions).to receive(:execute).and_raise(RuntimeError, "kaboom")
      run = execute(run_for(txn))
      expect(run.status).to eq(WorkflowRun::Status::Failed)
      expect(ActivityEntry.where(caused_by: run).count).to eq(1)
    end
  end

  describe "failure handling" do
    it "marks the run failed and records the error when execution raises" do
      txn = create(:cash_transaction, :bank, account: account)
      workflow.replace_steps!([
        { kind: "action", config: { action_type: "set_memo", params: { value: "x" } } }
      ])
      allow(Workflows::Actions).to receive(:execute).and_raise(RuntimeError, "kaboom")

      run = execute(run_for(txn))

      expect(run.status).to eq(WorkflowRun::Status::Failed)
      expect(run.error).to match(/kaboom/)
    end
  end
end
