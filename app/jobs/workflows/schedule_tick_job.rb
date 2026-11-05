# typed: true

module Workflows
  # The clock for schedule-triggered workflows: every few minutes, fire any
  # whose next_scheduled_at has passed and advance their clock hand. Runs are
  # subject-less (data actions skip; branches with conditions never match) —
  # scheduled workflows exist to drive side effects: syncs, audits,
  # notifications.
  class ScheduleTickJob < ApplicationJob
    extend T::Sig

    queue_as :workflows
    limits_concurrency to: 1, key: -> { "workflow_schedule_tick" }

    sig { void }
    def perform
      now = Time.current
      Workflow.unscoped.due_scheduled.find_each do |workflow|
        household = Household.find_by(id: workflow.household_id)
        next unless household

        run = T.let(nil, T.nilable(WorkflowRun))
        Current.set(household: household) do
          run = workflow.runs.create!(
            household_id:  workflow.household_id,
            subject_type:  nil,
            subject_id:    nil,
            event_type:    "schedule.fired",
            event_payload: { "scheduled_for" => workflow.next_scheduled_at&.iso8601 },
            status:        WorkflowRun::Status::Pending
          )
          ExecuteRunJob.perform_later(run.id)
          # Advance only after the run is created AND enqueued — advancing
          # past a failure silently skips the occurrence forever.
          workflow.advance_schedule!(from: now)
        end
      rescue => e
        # Leave next_scheduled_at in the past so the next 5-minute tick
        # retries. A persistently broken workflow will re-fail every tick;
        # we accept that (no attempt cap) and rely on the error-severity
        # activity below to surface it rather than track attempts in a
        # column we don't have.
        Rails.logger.error("[Workflows::ScheduleTickJob] workflow=#{workflow.id} #{e.class}: #{e.message}")
        # Don't strand a created-but-never-enqueued run in pending forever;
        # cancelled runs are visible in the run list and pruned normally.
        if run&.persisted?
          run.update(status: WorkflowRun::Status::Cancelled, error: "tick failed to enqueue: #{e.class}: #{e.message}",
                     finished_at: Time.current)
        end
        Activity.record(
          source:   "workflow",
          event:    "schedule.tick_failed",
          severity: Severity::Error,
          summary:  "Scheduled workflow \"#{workflow.name}\" could not fire: #{e.class}: #{e.message}",
          payload:  { workflow_id: workflow.id, scheduled_for: workflow.next_scheduled_at&.iso8601 },
          household_id: workflow.household_id
        )
      end
    end
  end
end
