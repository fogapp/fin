# typed: false

module Mcp
  module Tools
    class GetBudget < Base
      tool_name "get_budget"
      description "The household budget for a month: planned vs actual per " \
                  "category, rollovers, income target, and left-to-plan."
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
      input_schema(
        properties: {
          month: { type: "string", description: "Month as YYYY-MM (default: current month)" }
        },
        required: []
      )

      def self.call(server_context:, month: nil)
        date = month.present? ? Date.strptime(month, "%Y-%m") : Date.current
        # Same computation and payload as GET /budget, so it shares that
        # endpoint's cache entries.
        cached_json_response("budget", { "month" => month.presence }.compact, params: %i[month]) do
          Budgets::Month.new(month: date.beginning_of_month).call
        end
      end
    end
  end
end
