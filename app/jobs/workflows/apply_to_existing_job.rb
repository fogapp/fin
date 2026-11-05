# typed: true

module Workflows
  # Runs a workflow against the existing records of its trigger's subject
  # model — the "apply to past transactions" half of quick automations.
  # Root-level branch conditions prefilter (via the shared ConditionCheck)
  # so only matching records produce runs; workflows whose roots are plain
  # actions apply to everything.
  class ApplyToExistingJob < ApplicationJob
    extend T::Sig

    queue_as :workflows
    limits_concurrency to: 1, key: ->(workflow_id) { workflow_id }

    MAX_RUNS = 5_000

    sig { params(workflow_id: String).void }
    def perform(workflow_id)
      with_record(Workflow, workflow_id) do |workflow|
        subject_class = Workflows::Catalog.subject_class_for(workflow.trigger_type)&.safe_constantize
        next unless subject_class

        dispatched = T.let(0, Integer)

        subject_class.find_each do |record|
          break if dispatched >= MAX_RUNS
          next unless workflow.roots_match?(record)

          run = workflow.runs.create!(
            household_id:  workflow.household_id,
            subject_type:  record.class.name,
            subject_id:    record.id,
            event_type:    "manual.apply_to_existing",
            event_payload: {},
            status:        WorkflowRun::Status::Pending
          )
          ExecuteRunJob.perform_later(run.id)
          dispatched += 1
        end

        Activity.record(
          source: "workflow", event: "apply_to_existing.dispatched",
          summary: "Workflow \"#{workflow.name}\" applied to #{dispatched} existing record#{dispatched == 1 ? '' : 's'}",
          subject: workflow, payload: { dispatched: dispatched },
          household_id: workflow.household_id
        )
      end
    end
  end
end
