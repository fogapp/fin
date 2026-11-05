# typed: strict

module Audits
  # Nothing else watches SolidQueue::FailedExecution — a job that exhausts its
  # retries lands there silently. Surface (never prune) failed executions as an
  # error-severity issue with the failing job classes so they get investigated.
  class FailedJobs
    extend T::Sig

    sig { void }
    def call
      counts = SolidQueue::FailedExecution.joins(:job).group("solid_queue_jobs.class_name").count

      if counts.any?
        total = counts.values.sum
        breakdown = counts.sort_by { |_, n| -n }.map { |klass, n| "#{klass} ×#{n}" }.join(", ")
        Issue.raise_once!(
          key:      "solid_queue_failed_jobs",
          title:    "#{total} background job#{total == 1 ? '' : 's'} failed permanently",
          body:     "Solid Queue has failed executions that exhausted their retries: #{breakdown}. " \
                    "Inspect and retry or discard them from the Solid Queue tables (solid_queue_failed_executions).",
          severity: Severity::Error,
          source:   "system_audit"
        )
        Activity.record(
          source: "system_audit", event: "jobs.failed_executions", severity: Severity::Error,
          summary: "#{total} failed background job execution#{total == 1 ? '' : 's'} pending: #{breakdown}",
          payload: { failed_executions: counts }
        )
      else
        Issue.resolve!("solid_queue_failed_jobs")
      end
    end
  end
end
