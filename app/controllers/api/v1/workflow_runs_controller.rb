# typed: true

module Api
  module V1
    class WorkflowRunsController < BaseController
      renders_with Api::Render::WorkflowRun

      # Wire-only value returned by #revert. Reverting is an overlay on a
      # finished run (reverted_at), not a WorkflowRun::Status — it never
      # appears in the status column.
      REVERTED_DISPLAY_STATUS = "reverted"

      def index
        # run_steps ride along because serialize derives `revertible` from
        # them — without the include that's one query per run row.
        scope = WorkflowRun.recent.includes(:workflow, :run_steps)
        scope = scope.where(workflow_id: params[:workflow_id]) if params[:workflow_id].present?
        status = enum_param(WorkflowRun::Status, :status)
        scope = scope.where(status: status) if status
        scope = scope.where(trace_id: params[:trace_id]) if params[:trace_id].present?

        return render_grouped(scope) if params[:grouped].present?

        runs, meta = paginate(scope)
        render json: {
          runs: runs.map { |r| renderer.serialize(r) },
          meta: meta
        }
      end

      def revert
        run = WorkflowRun.find(params[:id])
        result = Workflows::Revert.call(run)
        render json: {
          status: REVERTED_DISPLAY_STATUS,
          reverted: result.reverted, conflicted: result.conflicted, skipped: result.skipped
        }
      end

      def show
        run = WorkflowRun.includes(run_steps: :workflow_step).find(params[:id])
        render json: renderer.serialize(run, include_steps: true)
      end

      private

      # One row per causal episode: all runs sharing a trace_id (one manual
      # run-now pass, one import burst, one sync) collapse into a group.
      # Single-run groups carry the serialized run so the client renders
      # them exactly like ungrouped rows.
      def render_grouped(scope)
        page = page_param
        grouping = TraceGrouping.new(scope: scope,
                                     key: [ :workflow_id, :trace_id, :event_type ],
                                     timestamp: :created_at)
        result = grouping.page(page)
        page_keys = result.page_keys

        # A trace can span workflows (one event burst, several listeners), so
        # every aggregate keys on the full (workflow, trace, event) tuple.
        trace_ids = page_keys.map { |k| k[1] }
        page_scope = scope.unscope(:order, :includes).where(trace_id: trace_ids)
        # One pass over the grouped counts, bucketed by tuple, instead of
        # rescanning the whole hash for every group.
        statuses_by_tuple = Hash.new { |h, k| h[k] = {} }
        page_scope.group(:workflow_id, :trace_id, :event_type, :status).count
                  .each { |(w, t, e, status), n| statuses_by_tuple[[ w, t, e ]][status] = n }
        reverted_counts = page_scope.where.not(reverted_at: nil)
                                    .group(:workflow_id, :trace_id, :event_type).count
        workflows = Workflow.where(id: page_keys.map(&:first).uniq).index_by(&:id)
        # From the filtered scope, so a status/workflow filter can't pull in
        # a sibling run the group count never included.
        single_runs = scope.unscope(:order)
                           .where(trace_id: page_keys.select { |k| k[3] == 1 }.map { |k| k[1] })
                           .group_by { |r| [ r.workflow_id, r.trace_id, r.event_type ] }

        groups = page_keys.map do |workflow_id, trace_id, event_type, count, first_at, last_at|
          tuple = [ workflow_id, trace_id, event_type ]
          statuses = statuses_by_tuple.fetch(tuple, {})
          single = count == 1 ? single_runs[tuple]&.first : nil
          {
            trace_id:      trace_id,
            workflow_id:   workflow_id,
            workflow_name: workflows[workflow_id]&.name,
            event_type:    event_type,
            count:         count,
            statuses:      statuses,
            reverted:      reverted_counts[tuple] || 0,
            first_at:      first_at.iso8601,
            last_at:       last_at.iso8601,
            run:           single ? renderer.serialize(single) : nil
          }
        end

        render json: {
          groups: groups,
          meta: { page: page, per_page: grouping.per_page, total: result.total }
        }
      end
    end
  end
end
