# typed: true

# Model Context Protocol endpoint (Streamable HTTP transport, JSON-RPC over
# POST /mcp). Runs in-process with the rest of the app, so it ships with the
# default `web` process — nothing extra to launch locally or in production.
#
# Clients authenticate with the same bearer ApiTokens as the REST API; auth
# populates Current, and the HouseholdScoped default scopes confine every
# tool to the token's household exactly as they do for REST requests.
class McpController < ActionController::API
  include ApiTokenAuthentication
  include TracesRequest

  before_action :authenticate_with_token!
  # `require: false` in the Gemfile — #server names MCP::Server as the receiver
  # of the constructor, which Ruby resolves before it evaluates the arguments
  # that would autoload Mcp::Tools (and with it the require in Tools::Base).
  before_action :load_mcp!

  def handle
    # A new MCP::Server per request: the transport is stateless (no SSE, no
    # session IDs), tools are stateless classes, and per-request state lives
    # in Current — the same model as the REST controllers.
    payload = server.handle_json(request.body.read)

    if payload.nil?
      # JSON-RPC notifications (e.g. notifications/initialized) have no
      # response body; the Streamable HTTP spec says return 202.
      head :accepted
    else
      render json: payload
    end
  end

  # Streamable HTTP optional methods we don't support: GET opens an SSE
  # stream, DELETE ends a session. The spec allows a plain 405 for both.
  # Declaring GET here also keeps /mcp out of the SPA catch-all route.
  def method_not_allowed
    head :method_not_allowed
  end

  private

  # Every tool reads, so a read-scoped token may call any of them.
  def read_only_request?
    true
  end

  def server
    MCP::Server.new(
      name:    "fin",
      title:   "Fin",
      version: "1.0.0",
      instructions: "Fin is a personal finance hub. Tools are read-only " \
                    "and scoped to the authenticated household; all amounts " \
                    "are USD unless a currency field says otherwise.",
      tools: Mcp::Tools.all,
      server_context: { user: Current.user, household: Current.household }
    )
  end

  def load_mcp!
    require "mcp"
  end
end
