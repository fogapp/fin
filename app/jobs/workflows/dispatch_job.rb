# typed: true

module Workflows
  # Fans a published event out to every active workflow listening for it:
  # one WorkflowRun per (event, workflow), executed asynchronously.
  class DispatchJob < ApplicationJob
    extend T::Sig

    queue_as :workflows

    sig do
      params(event_type: String, household_id: String, subject_type: String,
             subject_id: String, payload: T::Hash[T.untyped, T.untyped],
             triggered_by_run_id: T.nilable(String)).void
    end
    def perform(event_type, household_id, subject_type, subject_id, payload, triggered_by_run_id: nil)
      household = Household.find_by(id: household_id)
      return unless household

      Current.set(household: household) do
        trigger_types = [ event_type, Catalog.any_alias_for(event_type) ].compact
        # Below debug level, workflows whose root branches reject the subject
        # are skipped before a run row ever exists — the executor would only
        # record a not_matched no-op. Debug keeps the old fan-out so users
        # can see exactly which workflows were checked. Subjects that can't
        # be loaded (deleted-record events) skip the prefilter and keep the
        # executor's own handling.
        prefilter = household.workflow_log_level != LogLevel::Debug
        subject   = subject_type.safe_constantize&.find_by(id: subject_id) if prefilter
        # A replay (Plaid rewrote a pending row's descriptor/amount after the
        # original event fired) re-offers the subject to workflows that
        # rejected it the first time; ones that already matched keep their
        # single run rather than applying their actions twice.
        replay    = payload["replay"].present?

        workflows = Workflow.active.where(trigger_type: trigger_types).order(:position)
        # One read of every listener's steps for the root-branch prefilter,
        # not one per workflow — a busy trigger has hundreds of listeners.
        workflows = workflows.includes(:steps) if prefilter && subject

        workflows.each do |workflow|
          next unless workflow.trigger_matches?(payload)
          next if prefilter && subject && !workflow.roots_match?(subject)
          next if replay && already_acted?(workflow, subject_type, subject_id, event_type)

          run = workflow.runs.create!(
            household:           household,
            subject_type:        subject_type,
            subject_id:          subject_id,
            event_type:          event_type,
            event_payload:       payload,
            status:              WorkflowRun::Status::Pending,
            triggered_by_run_id: triggered_by_run_id
          )
          ExecuteRunJob.perform_later(run.id)
        end
      end
    end

    private

    sig { params(workflow: Workflow, subject_type: String, subject_id: String, event_type: String).returns(T::Boolean) }
    def already_acted?(workflow, subject_type, subject_id, event_type)
      WorkflowRunStep
        .joins(:workflow_run)
        .where(workflow_runs: { workflow_id: workflow.id, subject_type: subject_type,
                                subject_id: subject_id, event_type: event_type })
        .where(status: [ WorkflowRunStep::Status::Matched.serialize, WorkflowRunStep::Status::Applied.serialize ])
        .exists?
    end
  end
end
