# typed: strict

module Api
  module Render
    class ActivityEntry < Api::Render::Base
      extend T::Sig

      sig { params(entry: ::ActivityEntry).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(entry)
        {
          id:           entry.id,
          occurred_at:  entry.occurred_at.iso8601,
          source:       entry.source,
          event:        entry.event,
          severity:     entry.severity,
          summary:      entry.summary,
          payload:      entry.payload,
          subject_type: entry.subject_type,
          subject_id:   entry.subject_id,
          trace_id:     entry.trace_id,
          caused_by_type: entry.caused_by_type,
          caused_by_id:   entry.caused_by_id,
          duration_ms:  entry.duration_ms
        }
      end

      # Everything in one causal episode: the entries plus the workflow runs
      # and notifications stamped with the same trace.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def trace
        trace_id = params[:trace_id]
        run_renderer = Api::Render::WorkflowRun.new(params: params)

        {
          trace_id:      trace_id,
          entries:       ::ActivityEntry.for_trace(trace_id).order(:occurred_at).map { |e| serialize(e) },
          workflow_runs: ::WorkflowRun.where(trace_id: trace_id).order(:created_at)
                                      .includes(:workflow, :run_steps).map { |r| run_renderer.serialize(r) },
          notifications: ::Notification.where(trace_id: trace_id).order(:created_at).map { |n|
            { id: n.id, title: n.title, severity: n.severity, created_at: n.created_at.iso8601 }
          }
        }
      end
    end
  end
end
