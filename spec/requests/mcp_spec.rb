require "rails_helper"

RSpec.describe "MCP endpoint", type: :request do
  let(:token)   { create(:api_token) }
  let(:headers) { { "Authorization" => "Bearer #{token.raw_token}", "CONTENT_TYPE" => "application/json" } }

  def rpc(method, params = nil, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.compact.to_json
  end

  describe "authentication" do
    it "returns 401 without a token" do
      post "/mcp", params: rpc("tools/list")
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for an invalid token" do
      post "/mcp", params: rpc("tools/list"), headers: headers.merge("Authorization" => "Bearer nope")
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "transport" do
    it "rejects GET and DELETE with 405" do
      get "/mcp", headers: headers
      expect(response).to have_http_status(:method_not_allowed)

      delete "/mcp", headers: headers
      expect(response).to have_http_status(:method_not_allowed)
    end

    it "answers the initialize handshake" do
      post "/mcp", params: rpc("initialize", {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "spec", version: "0" }
      }), headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig("result", "serverInfo", "name")).to eq("fin")
      expect(body.dig("result", "capabilities")).to include("tools")
    end

    # The stateless lifecycle (MCP 2026-07-28): no initialize handshake, each
    # request carries its protocol version and client capabilities in _meta.
    # A fresh MCP::Server per request is exactly that model.
    it "serves a stateless request that carries its envelope in _meta" do
      create(:account)
      post "/mcp", params: rpc("tools/call", {
        name: "list_accounts",
        arguments: {},
        _meta: {
          "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
          "io.modelcontextprotocol/clientCapabilities" => {}
        }
      }), headers: headers

      expect(response).to have_http_status(:ok)
      result = response.parsed_body["result"]
      expect(result["isError"]).to be(false)
      expect(JSON.parse(result.dig("content", 0, "text"))).not_to be_empty
    end

    it "returns 202 with no body for notifications" do
      post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: headers
      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_blank
    end
  end

  describe "tools/list" do
    it "lists the read-only household tools" do
      post "/mcp", params: rpc("tools/list"), headers: headers

      names = response.parsed_body.dig("result", "tools").map { |t| t["name"] }
      expect(names).to contain_exactly(
        "list_accounts", "search_transactions", "get_net_worth",
        "get_cashflow", "get_budget", "get_dashboard"
      )
      annotations = response.parsed_body.dig("result", "tools").map { |t| t.dig("annotations", "readOnlyHint") }
      expect(annotations).to all(be(true))
    end
  end

  describe "tools/call" do
    it "returns accounts as a JSON text block" do
      account = create(:account)

      post "/mcp", params: rpc("tools/call", { name: "list_accounts", arguments: {} }), headers: headers

      result = response.parsed_body["result"]
      expect(result["isError"]).to be(false)
      rows = JSON.parse(result.dig("content", 0, "text"))
      expect(rows.map { |r| r["id"] }).to include(account.id)
    end

    it "filters transactions by description and honors the limit" do
      create(:cash_transaction, description: "Blue Bottle Coffee", amount: -6.5)
      create(:cash_transaction, description: "Paycheck", amount: 2500)

      post "/mcp", params: rpc("tools/call", {
        name: "search_transactions",
        arguments: { description: "coffee", limit: 10 }
      }), headers: headers

      rows = JSON.parse(response.parsed_body.dig("result", "content", 0, "text"))
      expect(rows.length).to eq(1)
      expect(rows.first["description"]).to eq("Blue Bottle Coffee")
    end

    it "scopes results to the token's household" do
      mine = create(:cash_transaction, description: "Mine")

      other_household = Household.create!(name: "Other")
      Current.set(household: other_household) do
        create(:cash_transaction, description: "Theirs")
      end

      post "/mcp", params: rpc("tools/call", { name: "search_transactions", arguments: {} }), headers: headers

      descriptions = JSON.parse(response.parsed_body.dig("result", "content", 0, "text")).map { |r| r["description"] }
      expect(descriptions).to include("Mine")
      expect(descriptions).not_to include("Theirs")
      expect(descriptions).to include(mine.description)
    end

    it "returns a JSON-RPC error, not a 500, when a tool gets bad input" do
      post "/mcp", params: rpc("tools/call", { name: "get_budget", arguments: { month: "bogus" } }), headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["error"]).to be_present
    end

    it "rejects arguments that violate the input schema" do
      post "/mcp", params: rpc("tools/call", {
        name: "search_transactions", arguments: { limit: "many" }
      }), headers: headers

      result = response.parsed_body["result"]
      expect(result["isError"]).to be(true)
    end
  end
end
