# typed: true

module Workflows
  # Bulk undo: reverts every non-reverted run of a workflow (newest first,
  # so layered changes unwind in order), then records one summary activity
  # entry instead of one per run.
  class RevertRunsJob < ApplicationJob
    extend T::Sig

    queue_as :workflows
    limits_concurrency to: 1, key: ->(workflow_id, since = nil) { workflow_id }

    sig { params(workflow_id: String, since: T.nilable(String)).void }
    def perform(workflow_id, since = nil)
      with_record(Workflow, workflow_id) do |workflow|
        runs = workflow.runs.where(reverted_at: nil).order(created_at: :desc)
        runs = runs.where(created_at: Time.iso8601(since)..) if since

        totals = { runs: 0, reverted: 0, conflicted: 0 }
        runs.find_each do |run|
          result = Workflows::Revert.call(run, record_activity: false)
          totals[:runs] += 1
          totals[:reverted]   += result.reverted
          totals[:conflicted] += result.conflicted
        end

        Activity.record(
          source: "workflow", event: "runs.reverted",
          summary: "Reverted workflow \"#{workflow.name}\": #{totals[:reverted]} " \
                   "change#{totals[:reverted] == 1 ? '' : 's'} restored across #{totals[:runs]} runs" \
                   "#{totals[:conflicted].positive? ? ", #{totals[:conflicted]} kept (changed since)" : ''}",
          subject: workflow, payload: totals,
          household_id: workflow.household_id
        )
      end
    end
  end
end
