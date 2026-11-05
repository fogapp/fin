# typed: false

module Mcp
  module Tools
    class GetDashboard < Base
      tool_name "get_dashboard"
      description "Investment dashboard: portfolio value and chart, asset " \
                  "allocation, income series, activity, and monthly spend."
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)

      def self.call(server_context:)
        cached_json_response("dashboard", params: %i[broker_id from]) do
          Api::Render::Dashboard.new(params: {}).index
        end
      end
    end
  end
end
