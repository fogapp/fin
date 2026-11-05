# typed: true

module Api
  module V1
    class ActivityController < BaseController
      renders_with Api::Render::ActivityEntry

      def index
        scope = ActivityEntry.recent
        scope = scope.where(source: params[:source].split(",")) if params[:source].present?
        scope = scope.where(severity: enum_param(Severity, :severity)) if params[:severity].present?
        if params[:subject_type].present? && params[:subject_id].present?
          scope = scope.where(subject_type: params[:subject_type], subject_id: params[:subject_id])
        end

        return render_grouped(scope) if params[:grouped].present?

        entries, meta = paginate(scope)
        render json: {
          entries: entries.map { |e| renderer.serialize(e) },
          meta:    meta
        }
      end

      # Everything in one causal episode — entries, workflow runs and
      # notifications stamped with the same trace; shaped by the renderer.
      def trace
        render json: renderer.trace
      end

      private

      GROUP_KEY = Arel.sql("COALESCE(trace_id::text, id::text)")

      # One timeline row per causal episode: entries sharing a trace_id
      # collapse; entries without a trace stay singletons. The lead entry
      # (worst severity, then latest) carries the group's summary.
      def render_grouped(scope)
        page = page_param
        grouping = TraceGrouping.new(scope: scope, key: GROUP_KEY, timestamp: :occurred_at)
        result = grouping.page(page)
        page_keys = result.page_keys

        # Sargable member fetch: traced entries match on trace_id, untraced
        # ones on their own id (their group key) — both indexed, unlike the
        # old COALESCE(...)::text IN (?) which forced a sequential scan.
        keys = page_keys.map(&:first)
        base = scope.unscope(:order)
        entries_by_key = base.where(trace_id: keys)
                             .or(base.where(trace_id: nil, id: keys))
                             .group_by { |e| (e.trace_id || e.id).to_s }

        groups = page_keys.map do |key, count, first_at, last_at|
          members = entries_by_key.fetch(key, [])
          lead = members.max_by { |e| [ e.severity.is_a?(Severity) ? e.severity.rank : 0, e.occurred_at ] }
          next if lead.nil?

          {
            trace_id:   members.first.trace_id,
            count:      count,
            severities: members.map(&:severity).tally,
            sources:    members.map(&:source).uniq.sort,
            first_at:   first_at.iso8601,
            last_at:    last_at.iso8601,
            lead:       renderer.serialize(lead)
          }
        end.compact

        render json: {
          groups: groups,
          meta: { page: page, per_page: grouping.per_page, total: result.total }
        }
      end
    end
  end
end
