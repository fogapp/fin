# typed: true

module Workflows
  # Runs killed mid-execution (deploy, OOM, SIGKILL) stay status "running"
  # forever — the executor's ensure never ran. Re-executing is safe:
  # Executor#resumable_status? includes "running", and it restarts from the
  # root against the reloaded subject. Runs stranded for more than a day are
  # presumed unrecoverable (every 30-minute sweep since has failed to finish
  # them) and are marked failed with an error-severity activity.
  class StrandedRunSweepJob < ApplicationJob
    extend T::Sig

    queue_as :workflows
    limits_concurrency to: 1, key: -> { "workflow_stranded_run_sweep" }

    STRANDED_AFTER = 30.minutes
    FAILED_AFTER   = 1.day

    sig { void }
    def perform
      stranded = WorkflowRun.unscoped
                            .where(status: WorkflowRun::Status::Running)
                            .where(started_at: ...STRANDED_AFTER.ago)

      stranded.where(started_at: ...FAILED_AFTER.ago).find_each { |run| fail_run(run) }

      stranded.where(started_at: FAILED_AFTER.ago...).find_each do |run|
        Rails.logger.info("[Workflows::StrandedRunSweepJob] re-enqueuing stranded run=#{run.id}")
        ExecuteRunJob.perform_later(run.id)
      end
    end

    private

    sig { params(run: WorkflowRun).void }
    def fail_run(run)
      r = T.unsafe(run)
      run.update!(status: WorkflowRun::Status::Failed, finished_at: Time.current,
                  error: "stranded in running for over #{FAILED_AFTER.inspect}; marked failed by sweep")
      Activity.record(
        source:   "workflow",
        event:    "run.stranded",
        severity: Severity::Error,
        summary:  "Workflow run #{run.id} was stuck in running since #{r.started_at&.iso8601} and was marked failed",
        payload:  { workflow_id: r.workflow_id, run_id: run.id, event_type: r.event_type },
        household_id: r.household_id
      )
    end
  end
end
