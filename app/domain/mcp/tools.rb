# typed: false

module Mcp
  # Household-scoped, read-only MCP tools. Each tool wraps the same renderer
  # or service its REST endpoint uses, so an MCP client and the SPA always
  # see identical payloads. Scoping comes from Current (set by the MCP
  # controller during token auth), not from the tool arguments — a token can
  # never reach outside its household.
  module Tools
    # Registered on every MCP::Server the controller builds; the order here
    # is the order clients see from tools/list.
    def self.all
      [
        ListAccounts,
        SearchTransactions,
        GetNetWorth,
        GetCashflow,
        GetBudget,
        GetDashboard
      ]
    end
  end
end
