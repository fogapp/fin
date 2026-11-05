# typed: strict

module Workflows
  module Actions
    # Dispatches another workflow against the same subject. The new run
    # inherits this run's ancestry, so the executor's cycle and depth guards
    # apply to the whole chain.
    class RunWorkflow
      extend T::Sig

      sig do
        params(params: T::Hash[String, T.untyped], run: WorkflowRun, subject: T.untyped)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def call(params, run:, subject:)
        target = Workflow.find_by(id: params["workflow_id"], household_id: run.household_id)
        return { status: :error, error: "workflow not found" } if target.nil?
        return { status: :skipped, reason: "target workflow is inactive" } unless target.active?

        child = target.runs.create!(
          household_id:        run.household_id,
          subject_type:        run.subject_type,
          subject_id:          run.subject_id,
          event_type:          run.event_type,
          event_payload:       run.event_payload,
          status:              WorkflowRun::Status::Pending,
          triggered_by_run_id: run.id
        )
        ExecuteRunJob.perform_later(child.id)

        { status: :applied, run_id: child.id }
      end
    end
  end
end
