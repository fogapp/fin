# typed: false

module Mcp
  module Tools
    class GetCashflow < Base
      tool_name "get_cashflow"
      description "Income vs spending summary with per-category breakdowns " \
                  "for a date range (defaults to the current month)."
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
      input_schema(
        properties: {
          from: { type: "string", description: "ISO start date (inclusive)" },
          to:   { type: "string", description: "ISO end date (inclusive)" }
        },
        required: []
      )

      def self.call(server_context:, from: nil, to: nil)
        args = { "from" => from, "to" => to }.compact
        cached_json_response("cashflow", args, params: Api::V1::CashflowController::CACHE_PARAMS) do
          Api::Render::Cashflow.new(params: render_params(args)).index
        end
      end
    end
  end
end
