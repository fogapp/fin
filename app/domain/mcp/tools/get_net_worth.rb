# typed: false

module Mcp
  module Tools
    class GetNetWorth < Base
      tool_name "get_net_worth"
      description "Current net worth and its history over a named window, " \
                  "broken down by asset class."
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
      input_schema(
        properties: {
          range: {
            type: "string",
            enum: NetWorthHistory::RangeKey.values.map(&:serialize),
            description: "Chart window (default #{NetWorthHistory::DEFAULT_RANGE.serialize})"
          }
        },
        required: []
      )

      def self.call(server_context:, range: nil)
        key = NetWorthHistory::RangeKey.try_deserialize(range.to_s)
        # Same computation and payload as GET /net_worth (which renders
        # NetWorthHistory with no explicit from/to), so it shares that
        # endpoint's cache entries. An absent or unrecognized range keys the
        # same as a REST request with no ?range, which also means the default.
        args = key ? { "range" => key.serialize } : {}
        cached_json_response("net_worth", args, params: %i[range from to]) do
          NetWorthHistory.new(range: key || NetWorthHistory::DEFAULT_RANGE).call
        end
      end
    end
  end
end
