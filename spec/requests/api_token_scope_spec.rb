require "rails_helper"

# A token's scope is enforced in one place, ApiTokenAuthentication, for the
# REST API and the MCP endpoint alike.
RSpec.describe "API token scope", type: :request do
  let(:read)    { create(:api_token, name: "reader", scope: ApiToken::Scope::Read) }
  let(:full)    { create(:api_token, name: "writer") }
  let(:headers) { { "Authorization" => "Bearer #{read.raw_token}" } }

  def rpc(method, params = nil, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.compact.to_json
  end

  it "defaults to full, which does whatever its user can" do
    expect(full.scope).to eq(ApiToken::Scope::Full)
    expect(full).not_to be_read_only

    post "/api/v1/api_tokens", params: { name: "another" }, headers: { "Authorization" => "Bearer #{full.raw_token}" }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["scope"]).to eq("full")
  end

  it "lets a read token GET" do
    get "/api/v1/me", headers: headers
    expect(response).to have_http_status(:ok)

    get "/api/v1/net_worth", headers: headers
    expect(response).to have_http_status(:ok)
  end

  it "refuses a read token anything but a read, with a sentence" do
    {
      post:   [ "/api/v1/api_tokens", { name: "x" } ],
      patch:  [ "/api/v1/preferences", { theme: "dark" } ],
      put:    [ "/api/v1/preferences", { theme: "dark" } ],
      delete: [ "/api/v1/api_tokens/#{read.id}", nil ]
    }.each do |verb, (path, body)|
      public_send(verb, path, params: body, headers: headers, as: :json)
      expect(response).to have_http_status(:forbidden), "#{verb} #{path} answered #{response.status}"
      expect(response.parsed_body["error"]).to eq("This token can only read Fin, not change it.")
    end
    expect(ApiToken.unscoped.where(name: "x")).not_to exist
    expect(ApiToken.unscoped.exists?(read.id)).to be(true)
  end

  it "lets a read token use the MCP tools, which all read" do
    post "/mcp", params: rpc("tools/list"), headers: headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("result", "tools")).to be_present
  end

  it "lists the scope with each token" do
    read
    get "/api/v1/api_tokens", headers: { "Authorization" => "Bearer #{full.raw_token}" }
    scopes = response.parsed_body.to_h { |t| [ t["name"], t["scope"] ] }
    expect(scopes).to include("reader" => "read", "writer" => "full")
  end
end
