# typed: false

# The gem is `require: false` in the Gemfile and this file subclasses
# ::MCP::Tool in its class body, so the require has to happen here rather than
# at a call site. app/domain/mcp is excluded from eager loading (see
# application.rb), which is what keeps this file — and json_schemer with it —
# off the boot path until something actually reaches for an MCP tool.
require "mcp"

module Mcp
  module Tools
    class Base < ::MCP::Tool
      class << self
        private

        # Every Fin tool returns one JSON text block — MCP clients parse
        # the payload rather than reading prose.
        def json_response(data)
          ::MCP::Tool::Response.new([ { type: "text", text: JSON.generate(data) } ])
        end

        # The Api::Render classes read request params via [] with string or
        # symbol keys; indifferent access keeps both spellings working when
        # we feed them tool arguments instead of controller params.
        def render_params(args)
          ActiveSupport::HashWithIndifferentAccess.new(args.compact)
        end

        # Api::V1::BaseController#render_cached minus the HTTP/ETag half —
        # the key comes from the same Api::ResponseCache recipe, so an MCP
        # call shares the REST endpoint's cache entries instead of
        # recomputing a heavy renderer on every LLM tool call. Callers pass
        # the REST endpoint's own whitelist constant so the two can't drift.
        def cached_json_response(name, args = {}, params: [], expires_in: 5.minutes, &block)
          key = Api::ResponseCache.key(name, args, params: params)
          json = Api::ResponseCache.fetch_json(key, expires_in: expires_in, &block)
          ::MCP::Tool::Response.new([ { type: "text", text: json } ])
        end
      end
    end
  end
end
