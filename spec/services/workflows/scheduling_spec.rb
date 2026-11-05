require "rails_helper"

RSpec.describe "Workflow scheduling" do
  def scheduled_workflow(config: { "frequency" => "daily", "at" => "05:00" }, target: "system_audit")
    workflow = create(:workflow, name: "Scheduled #{target}", trigger_type: "schedule",
                      trigger_config: config)
    workflow.replace_steps!([
      { kind: "action", config: { "action_type" => "trigger_sync", "params" => { "target" => target } } }
    ])
    workflow
  end

  describe "model integration" do
    it "computes next_scheduled_at on create and validates config shape" do
      workflow = scheduled_workflow
      expect(workflow.next_scheduled_at).to be > Time.current

      invalid = build(:workflow, trigger_type: "schedule", trigger_config: { "frequency" => "sometimes" })
      expect(invalid).not_to be_valid
      expect(invalid.errors[:trigger_config].join).to match(/frequency/)
    end

    it "recomputes when the schedule config changes" do
      workflow = scheduled_workflow
      original = workflow.next_scheduled_at

      workflow.update!(trigger_config: { "frequency" => "hourly", "every_hours" => 1 })
      expect(workflow.reload.next_scheduled_at).not_to eq(original)
      expect(workflow.next_scheduled_at).to be <= 1.hour.from_now
    end
  end

  describe Workflows::ScheduleTickJob do
    it "fires due workflows as subject-less runs and advances the clock" do
      workflow = scheduled_workflow
      workflow.update_column(:next_scheduled_at, 1.minute.ago)

      expect {
        described_class.perform_now
      }.to have_enqueued_job(Workflows::ExecuteRunJob)

      run = workflow.runs.sole
      expect(run.subject_type).to be_nil
      expect(run.event_type).to eq("schedule.fired")
      expect(workflow.reload.next_scheduled_at).to be > Time.current
    end

    it "leaves workflows that are not due alone" do
      scheduled_workflow # next_scheduled_at in the future

      expect {
        described_class.perform_now
      }.not_to have_enqueued_job(Workflows::ExecuteRunJob)
    end

    it "skips inactive workflows" do
      workflow = scheduled_workflow
      workflow.update!(active: false)
      workflow.update_column(:next_scheduled_at, 1.minute.ago)

      expect { described_class.perform_now }.not_to have_enqueued_job(Workflows::ExecuteRunJob)
    end

    it "does not advance the schedule when firing fails, so the next tick retries" do
      workflow = scheduled_workflow
      due_at = 1.minute.ago
      workflow.update_column(:next_scheduled_at, due_at)
      allow(Workflows::ExecuteRunJob).to receive(:perform_later).and_raise("queue down")

      expect { described_class.perform_now }.not_to raise_error

      expect(workflow.reload.next_scheduled_at).to be_within(1.second).of(due_at)
      entry = ActivityEntry.where(event: "schedule.tick_failed").sole
      expect(entry.severity).to eq(Severity::Error)
      expect(entry.summary).to include(workflow.name)
      # The created-but-never-enqueued run is cancelled, not stranded pending.
      expect(workflow.runs.sole.status).to eq(WorkflowRun::Status::Cancelled)
    end

    it "anchors hourly schedules to the previous occurrence so they don't drift" do
      workflow = scheduled_workflow(config: { "frequency" => "hourly", "every_hours" => 4 })
      base = Time.current.beginning_of_hour
      workflow.update_column(:next_scheduled_at, base - 3.minutes)

      travel_to base do
        described_class.perform_now
      end

      # Anchored to the scheduled slot (base - 3.minutes), not the tick time.
      expect(workflow.reload.next_scheduled_at)
        .to be_within(1.second).of(base - 3.minutes + 4.hours)
    end

    it "catches up a far-behind hourly schedule instead of replaying every missed slot" do
      workflow = scheduled_workflow(config: { "frequency" => "hourly", "every_hours" => 4 })
      workflow.update_column(:next_scheduled_at, 3.days.ago)

      described_class.perform_now

      # Advanced from max(previous, now - interval) → lands at ~now, then
      # resumes the normal cadence.
      expect(workflow.reload.next_scheduled_at).to be_within(1.minute).of(Time.current)
      expect(workflow.runs.count).to eq(1)
    end
  end

  describe "subject-less execution" do
    it "runs the trigger_sync action and completes" do
      workflow = scheduled_workflow(target: "reconciliation")
      run = workflow.runs.create!(
        household_id: workflow.household_id, subject_type: nil, subject_id: nil,
        event_type: "schedule.fired", event_payload: {}, status: "pending"
      )

      expect {
        Workflows::Executor.new(run).call
      }.to have_enqueued_job(Reconciliation::SweepJob)
      expect(run.reload.status).to eq(WorkflowRun::Status::Completed)
    end

    it "skips data actions gracefully without a subject" do
      workflow = create(:workflow, trigger_type: "schedule",
                        trigger_config: { "frequency" => "daily", "at" => "05:00" })
      merchant = create(:merchant)
      workflow.replace_steps!([
        { kind: "action", config: { "action_type" => "assign_merchant", "params" => { "merchant_id" => merchant.id } } }
      ])
      run = workflow.runs.create!(
        household_id: workflow.household_id, subject_type: nil, subject_id: nil,
        event_type: "schedule.fired", event_payload: {}, status: "pending"
      )

      Workflows::Executor.new(run).call

      expect(run.reload.status).to eq(WorkflowRun::Status::Completed)
      expect(run.run_steps.sole.status).to eq(WorkflowRunStep::Status::Skipped)
    end
  end

  describe Households::SeedDefaultWorkflows do
    it "seeds the default scheduled workflows exactly once" do
      household = Current.household
      Workflow.where.not(seed_key: nil).destroy_all

      first = described_class.call(household)
      expect(first).to eq(described_class::DEFAULTS.size + described_class::EVENT_DEFAULTS.size)

      again = described_class.call(household)
      expect(again).to eq(0)

      market = Workflow.find_by!(seed_key: "market_data_sync")
      expect(market.trigger_type).to eq("schedule")
      expect(market.next_scheduled_at).to be_present
      step = market.root_steps.sole
      expect(step.config["params"]).to eq({ "target" => "market_prices" })

      detection = Workflow.find_by!(seed_key: "recurring_detection")
      expect(detection.trigger_type).to eq("schedule")
      expect(detection.root_steps.sole.config["params"]).to eq({ "target" => "recurring_detection" })
    end
  end
end
