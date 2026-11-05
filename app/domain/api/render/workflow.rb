# typed: strict

module Api
  module Render
    class Workflow < Api::Render::Base
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def index
        last_runs = ::WorkflowRun
          .select("DISTINCT ON (workflow_id) workflow_id, status, created_at")
          .order("workflow_id, created_at DESC")
          .index_by(&:workflow_id)
        counts = ::WorkflowRun.group(:workflow_id).count

        ::Workflow.order(:position, :name).map do |w|
          last = last_runs[w.id]
          serialize(w).merge(
            run_count:       counts[w.id] || 0,
            last_run_status: last&.status,
            last_run_at:     last&.created_at&.iso8601
          )
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def show
        serialize(::Workflow.find(params[:id]), include_steps: true)
      end

      sig { params(workflow: ::Workflow, include_steps: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(workflow, include_steps: false)
        base = {
          id:             workflow.id,
          name:           workflow.name,
          description:    workflow.description,
          trigger_type:   workflow.trigger_type,
          trigger_config: workflow.trigger_config,
          active:         workflow.active?,
          position:       workflow.position,
          seed_key:       workflow.seed_key,
          next_scheduled_at: workflow.next_scheduled_at&.iso8601,
          schedule_summary:  workflow.schedule_trigger? ? Workflows::Schedule.describe(workflow.trigger_config) : nil,
          created_at:     workflow.created_at.iso8601,
          updated_at:     workflow.updated_at.iso8601
        }
        base[:steps] = workflow.steps_tree if include_steps
        base
      end
    end
  end
end
