# typed: false

module Mcp
  module Tools
    class ListAccounts < Base
      tool_name "list_accounts"
      description "List the household's financial accounts with balances, " \
                  "broker, kind, transaction counts, and current portfolio value."
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)

      def self.call(server_context:)
        # Same payload as GET /accounts, so it shares that endpoint's cache.
        cached_json_response("accounts") { Api::Render::Account.new(params: {}).index }
      end
    end
  end
end
