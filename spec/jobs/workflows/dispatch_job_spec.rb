require "rails_helper"

RSpec.describe Workflows::DispatchJob do
  let(:account) { create(:account) }
  let(:txn)     { create(:cash_transaction, :bank, account: account) }

  it "creates one pending run per matching active workflow and enqueues execution" do
    w1 = create(:workflow, name: "First", trigger_type: "cash_transaction.created")
    w2 = create(:workflow, name: "Second", trigger_type: "cash_transaction.created")
    create(:workflow, name: "Other trigger", trigger_type: "account.updated")
    create(:workflow, name: "Inactive", trigger_type: "cash_transaction.created", active: false)

    expect {
      described_class.perform_now("cash_transaction.created", Current.household.id,
                                  "CashTransaction", txn.id, {})
    }.to change(WorkflowRun, :count).by(2)
      .and have_enqueued_job(Workflows::ExecuteRunJob).exactly(2).times

    expect(WorkflowRun.pluck(:workflow_id)).to contain_exactly(w1.id, w2.id)
    expect(WorkflowRun.pluck(:status).uniq).to eq([ WorkflowRun::Status::Pending ])
  end

  it "applies the changed_fields trigger filter for updated events" do
    create(:workflow, trigger_type: "cash_transaction.updated",
           trigger_config: { "changed_fields" => [ "merchant_id" ] })

    expect {
      described_class.perform_now("cash_transaction.updated", Current.household.id,
                                  "CashTransaction", txn.id, { "changes" => [ "memo" ] })
    }.not_to change(WorkflowRun, :count)

    expect {
      described_class.perform_now("cash_transaction.updated", Current.household.id,
                                  "CashTransaction", txn.id, { "changes" => [ "merchant_id", "memo" ] })
    }.to change(WorkflowRun, :count).by(1)
  end

  describe "log-level prefiltering" do
    def dispatch
      described_class.perform_now("cash_transaction.created", Current.household.id,
                                  "CashTransaction", txn.id, {})
    end

    let!(:workflow) { create(:workflow, trigger_type: "cash_transaction.created") }
    let!(:branch) do
      create(:workflow_step, :branch, workflow: workflow).tap do |b|
        create(:workflow_step, workflow: workflow, parent: b)
      end
    end

    it "skips creating a run when no root branch matches the subject" do
      txn.update!(description: "GAS STATION")
      expect { dispatch }.not_to change(WorkflowRun, :count)
    end

    it "creates a run when a root branch matches" do
      txn.update!(description: "STARBUCKS #42")
      expect { dispatch }.to change(WorkflowRun, :count).by(1)
    end

    it "keeps non-matching runs at debug level" do
      Current.household.update!(workflow_log_level: Workflows::LogLevel::Debug)
      txn.update!(description: "GAS STATION")
      expect { dispatch }.to change(WorkflowRun, :count).by(1)
    end

    it "always runs workflows with unconditional root actions" do
      branch.destroy!
      create(:workflow_step, workflow: workflow) # root action
      txn.update!(description: "GAS STATION")
      expect { dispatch }.to change(WorkflowRun, :count).by(1)
    end

    it "reads every listener's steps in one query, not one per workflow" do
      2.times do |i|
        w = create(:workflow, name: "Listener #{i}", trigger_type: "cash_transaction.created")
        create(:workflow_step, workflow: w, parent: create(:workflow_step, :branch, workflow: w))
      end
      txn.update!(description: "STARBUCKS #42")

      queries = count_queries { expect { dispatch }.to change(WorkflowRun, :count).by(3) }

      expect(queries.grep(/FROM "workflow_steps"/).size).to eq(1)
    end
  end

  it "threads the triggering run through for chain tracking" do
    workflow = create(:workflow, trigger_type: "cash_transaction.updated")
    parent   = create(:workflow_run, workflow: workflow)

    described_class.perform_now("cash_transaction.updated", Current.household.id,
                                "CashTransaction", txn.id, {}, triggered_by_run_id: parent.id)

    expect(WorkflowRun.where.not(id: parent.id).sole.triggered_by_run_id).to eq(parent.id)
  end

  describe "replayed events (a Plaid row rewritten after creation)" do
    let!(:matched_before) { create(:workflow, name: "Already acted", trigger_type: "cash_transaction.created") }
    let!(:rejected_before) do
      create(:workflow, name: "Rejected the pending row", trigger_type: "cash_transaction.created").tap do |w|
        branch = create(:workflow_step, :branch, workflow: w)
        create(:workflow_step, workflow: w, parent: branch)
      end
    end

    def replay
      described_class.perform_now("cash_transaction.created", Current.household.id,
                                  "CashTransaction", txn.id, { "replay" => "posted", "changes" => [ "description" ] })
    end

    it "re-offers the row only to workflows that never acted on it" do
      prior = create(:workflow_run, workflow: matched_before, subject: txn, event_type: "cash_transaction.created")
      prior.run_steps.create!(status: "applied")
      txn.update!(description: "STARBUCKS #42")

      expect { replay }.to change(WorkflowRun, :count).by(1)
      expect(WorkflowRun.where.not(id: prior.id).sole.workflow_id).to eq(rejected_before.id)
    end

    it "counts a not_matched run as never having acted" do
      prior = create(:workflow_run, workflow: matched_before, subject: txn, event_type: "cash_transaction.created")
      prior.run_steps.create!(status: "not_matched")
      txn.update!(description: "STARBUCKS #42")

      expect { replay }.to change(WorkflowRun, :count).by(2)
    end

    it "does not dedupe an ordinary (non-replay) event" do
      prior = create(:workflow_run, workflow: matched_before, subject: txn, event_type: "cash_transaction.created")
      prior.run_steps.create!(status: "applied")
      txn.update!(description: "STARBUCKS #42")

      expect {
        described_class.perform_now("cash_transaction.created", Current.household.id, "CashTransaction", txn.id, {})
      }.to change(WorkflowRun, :count).by(2)
    end
  end
end
