require "rails_helper"

# MCP tools and their REST counterparts build cache keys through the same
# Api::ResponseCache recipe; this proves an entry written by one side is
# served to the other, so the heavy renderer runs once.
RSpec.describe "MCP/REST cache sharing", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:mcp_headers)  { auth_headers.merge("CONTENT_TYPE" => "application/json") }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  def call_tool(name, arguments = {})
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                           params: { name: name, arguments: arguments } }.to_json,
                 headers: mcp_headers
    expect(response.parsed_body.dig("result", "isError")).to be(false)
    response.parsed_body.dig("result", "content", 0, "text")
  end

  it "serves GET /cashflow from the entry get_cashflow wrote" do
    expect(Api::Render::Cashflow).to receive(:new).once.and_call_original

    mcp_json = call_tool("get_cashflow", { from: "2026-01-01", to: "2026-01-31" })
    get "/api/v1/cashflow", params: { from: "2026-01-01", to: "2026-01-31" }, headers: auth_headers

    expect(response.body).to eq(mcp_json)
  end

  it "serves GET /net_worth from the entry get_net_worth wrote" do
    expect(NetWorthHistory).to receive(:new).once.and_call_original

    mcp_json = call_tool("get_net_worth", { range: "1y" })
    get "/api/v1/net_worth", params: { range: "1y" }, headers: auth_headers

    expect(response.body).to eq(mcp_json)
  end

  it "serves list_accounts from the entry GET /accounts wrote" do
    create(:account)
    expect(Api::Render::Account).to receive(:new).once.and_call_original

    get "/api/v1/accounts", headers: auth_headers
    rest_json = response.body

    expect(call_tool("list_accounts")).to eq(rest_json)
  end

  it "keys a stringified MCP scalar the same as the equivalent query param" do
    Current.set(household: token.household) do
      rest = Api::ResponseCache.key("x", { "months" => "6", "ids" => [ "a" ] }, params: %i[months ids])
      mcp  = Api::ResponseCache.key("x", { months: 6, ids: [ "a" ] }, params: %i[months ids])
      expect(mcp).to eq(rest)
    end
  end
end
