require "rails_helper"

RSpec.describe Workflows::Revert do
  let(:merchant)  { create(:merchant, name: "Comcast") }
  let(:original)  { create(:merchant, name: "Corner Store") }
  let(:workflow)  { create(:workflow, name: "Assign Comcast", trigger_type: "cash_transaction.created") }

  def build_workflow_with_action(params)
    workflow.replace_steps!([ { kind: "action", config: { "action_type" => "assign_merchant", "params" => params } } ])
    Workflows::Events.reset_cache
    workflow
  end

  def run_against(txn)
    run = workflow.runs.create!(
      household_id: workflow.household_id, subject_type: "CashTransaction",
      subject_id: txn.id, event_type: "manual.test", event_payload: {}, status: "pending"
    )
    Workflows::Executor.new(run).call
    run.reload
  end

  describe "change capture" do
    it "records before/after deltas on the applied step" do
      build_workflow_with_action({ "merchant_id" => merchant.id })
      txn = create(:cash_transaction, :credit_card, :sale, merchant: original)

      run = run_against(txn)

      step = run.run_steps.sole
      expect(step.status).to eq(WorkflowRunStep::Status::Applied)
      expect(step.output["undo"]).to eq({ "merchant_id" => [ original.id, merchant.id ] })
    end

    it "captures tag additions as a tag_ids delta" do
      tag = create(:tag, name: "utilities")
      workflow.replace_steps!([ { kind: "action", config: { "action_type" => "add_tag", "params" => { "tag_id" => [ tag.id ] } } } ])
      txn = create(:cash_transaction, :credit_card, :sale)

      run = run_against(txn)

      expect(run.run_steps.sole.output["undo"]["tag_ids"]).to eq([ [], [ tag.id ] ])
    end
  end

  describe ".call" do
    it "restores the before-value and marks the run reverted" do
      build_workflow_with_action({ "merchant_id" => merchant.id })
      txn = create(:cash_transaction, :credit_card, :sale, merchant: original)
      run = run_against(txn)
      expect(txn.reload.merchant_id).to eq(merchant.id)

      result = described_class.call(run)

      expect(result.reverted).to eq(1)
      expect(txn.reload.merchant_id).to eq(original.id)
      expect(run.reload.reverted_at).to be_present
      expect(ActivityEntry.where(event: "run.reverted").sole.payload["reverted"]).to eq(1)
    end

    it "leaves values the user changed since (three-way conflict)" do
      build_workflow_with_action({ "merchant_id" => merchant.id })
      txn = create(:cash_transaction, :credit_card, :sale, merchant: original)
      run = run_against(txn)

      hand_fixed = create(:merchant, name: "Hand Fixed")
      txn.update!(merchant: hand_fixed)

      result = described_class.call(run)

      expect(result.conflicted).to eq(1)
      expect(result.reverted).to eq(0)
      expect(txn.reload.merchant_id).to eq(hand_fixed.id)
    end

    it "removes only the tags the run added, keeping manual additions" do
      workflow_tag = create(:tag, name: "utilities")
      manual_tag   = create(:tag, name: "keeper")
      workflow.replace_steps!([ { kind: "action", config: { "action_type" => "add_tag", "params" => { "tag_id" => [ workflow_tag.id ] } } } ])
      Workflows::Events.reset_cache
      txn = create(:cash_transaction, :credit_card, :sale)
      run = run_against(txn)

      txn.tags << manual_tag

      described_class.call(run)

      expect(txn.reload.tag_ids).to eq([ manual_tag.id ])
    end

    it "does not re-trigger workflows from the revert write" do
      build_workflow_with_action({ "merchant_id" => merchant.id })
      # A second workflow listening on cash_transaction.updated would fire on
      # any write to the transaction.
      trap = create(:workflow, name: "Trap", trigger_type: "cash_transaction.updated")
      Workflows::Events.reset_cache
      txn = create(:cash_transaction, :credit_card, :sale, merchant: original)
      run = run_against(txn)

      expect {
        described_class.call(run)
      }.not_to have_enqueued_job(Workflows::DispatchJob)
      expect(trap.runs.count).to eq(0)
    end

    it "is idempotent — a second revert is a no-op" do
      build_workflow_with_action({ "merchant_id" => merchant.id })
      txn = create(:cash_transaction, :credit_card, :sale, merchant: original)
      run = run_against(txn)

      described_class.call(run)
      txn.update!(merchant: merchant) # user re-applies by hand
      result = described_class.call(run)

      expect(result.reverted).to eq(0)
      expect(txn.reload.merchant_id).to eq(merchant.id)
    end

    it "skips gracefully when the subject was deleted" do
      build_workflow_with_action({ "merchant_id" => merchant.id })
      txn = create(:cash_transaction, :credit_card, :sale, merchant: original)
      run = run_against(txn)
      txn.destroy!

      result = described_class.call(run)
      expect(result.skipped).to eq(1)
    end
  end

  describe Workflows::RevertRunsJob do
    it "reverts every run of the workflow and records one summary entry" do
      build_workflow_with_action({ "merchant_id" => merchant.id })
      txns = 3.times.map { create(:cash_transaction, :credit_card, :sale, merchant: original) }
      runs = txns.map { |t| run_against(t) }

      described_class.perform_now(workflow.id)

      expect(txns.each(&:reload).map(&:merchant_id).uniq).to eq([ original.id ])
      expect(runs.each(&:reload).map(&:reverted_at)).to all(be_present)
      summary = ActivityEntry.where(event: "runs.reverted").sole
      expect(summary.payload).to include("runs" => 3, "reverted" => 3)
    end
  end
end
