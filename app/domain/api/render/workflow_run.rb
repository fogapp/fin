# typed: strict

module Api
  module Render
    class WorkflowRun < Api::Render::Base
      extend T::Sig

      sig { params(run: ::WorkflowRun, include_steps: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(run, include_steps: false)
        base = {
          id:            run.id,
          workflow_id:   run.workflow_id,
          workflow_name: run.workflow&.name,
          event_type:    run.event_type,
          event_payload: run.event_payload,
          subject_type:  run.subject_type,
          subject_id:    run.subject_id,
          status:        run.status,
          error:         run.error,
          started_at:    run.started_at&.iso8601,
          finished_at:   run.finished_at&.iso8601,
          created_at:    run.created_at.iso8601,
          reverted_at:   run.reverted_at&.iso8601,
          revertible:    run.reverted_at.nil? && run.run_steps.any? { |rs|
            rs.status == ::WorkflowRunStep::Status::Applied && rs.output.is_a?(Hash) && rs.output["undo"].present?
          }
        }
        if include_steps
          base[:steps] = run.run_steps.map { |rs|
            { id:          rs.id,
              step_id:     rs.workflow_step_id,
              step_kind:   rs.workflow_step&.kind,
              status:      rs.status,
              output:      rs.output,
              resume_at:   rs.resume_at&.iso8601,
              created_at:  rs.created_at.iso8601 }
          }
        end
        base
      end
    end
  end
end
