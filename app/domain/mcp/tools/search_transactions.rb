# typed: false

module Mcp
  module Tools
    class SearchTransactions < Base
      # The REST default (1,000 rows) is sized for the SPA's paged table;
      # an LLM context wants far fewer unless it asks for more.
      DEFAULT_LIMIT = 50

      tool_name "search_transactions"
      description "Search cash transactions, newest first. All filters are " \
                  "optional and combine with AND. Amounts are negative for " \
                  "spending and positive for income."
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
      input_schema(
        properties: {
          description: { type: "string",  description: "Case-insensitive substring match on the description" },
          start_date:  { type: "string",  description: "ISO date lower bound (inclusive), e.g. 2026-01-01" },
          end_date:    { type: "string",  description: "ISO date upper bound (inclusive)" },
          category_id: { type: "string", description: "Filter to one category UUID (see get_budget for ids)" },
          merchant_id: { type: "string", description: "Filter to one merchant UUID" },
          account_id:  { type: "string", description: "Filter to one account UUID (see list_accounts for ids)" },
          limit:       { type: "integer", description: "Max rows, default #{DEFAULT_LIMIT}, max 1000" },
          offset:      { type: "integer", description: "Rows to skip, for paging" }
        },
        required: []
      )

      def self.call(server_context:, **args)
        args[:limit] ||= DEFAULT_LIMIT
        json_response(Api::Render::CashTransaction.new(params: render_params(args)).index)
      end
    end
  end
end
