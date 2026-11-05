# typed: strict

module Office
  # Thin wrapper over an Office instance's MCP endpoint (POST /mcp):
  # stateless JSON-RPC over HTTP, bearer-authenticated with an Office API
  # token. Office exposes no REST route for "make me a spreadsheet from
  # this data" — `documents#import` wants multipart and answers with the
  # document but not its extent — while the MCP tools do exactly this job
  # (`create_sheet_from_csv`, `write_cells`) and answer with the sheet name
  # and range, which is what a refresh needs to know.
  #
  # Every call acts as the token's Office user, so the spreadsheets Fin
  # creates are owned by whoever minted the token. Fin never sends a
  # household or user id: scoping is the token's, not the argument's.
  class Client
    extend T::Sig

    # The message is safe to show a Fin user: it is either our own text
    # or the error string an Office tool wrote for a human to read.
    class Error < StandardError; end

    # Office answered, but the tool refused (an unknown document, a
    # spreadsheet the token's user may not edit, a missing codec host).
    class ToolError < Error; end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 60

    sig { params(configuration: T.nilable(OfficeConfiguration)).void }
    def initialize(configuration: nil)
      config = configuration || OfficeConfiguration.current
      base   = config.resolved_base_url
      token  = config.resolved_api_key
      raise Error, "Office is not configured (set base_url and api_key, or OFFICE_URL and OFFICE_API_TOKEN)" if base.blank? || token.blank?

      @base_url = T.let(base, String)
      @token    = T.let(token, String)
      @config   = T.let(config, OfficeConfiguration)
    end

    # Proves the token is accepted and the MCP endpoint is live, without
    # writing anything: tools/list is the cheapest authenticated read.
    sig { returns(T::Hash[String, T.untyped]) }
    def test_connection!
      result = rpc("tools/list", {})
      names  = Array(result["tools"]).filter_map { |tool| tool["name"] }
      missing = REQUIRED_TOOLS - names
      raise Error, "Office answered but is missing the spreadsheet tools (#{missing.join(', ')})" if missing.any?

      { "tools" => names }
    end

    REQUIRED_TOOLS = T.let(%w[create_sheet_from_csv write_cells].freeze, T::Array[String])

    # A new spreadsheet from CSV text. Answers Office's document row plus
    # `sheet`, `range` and `url`.
    sig do
      params(title: String, csv: String, folder_id: T.nilable(Integer), visibility: T.nilable(String))
        .returns(T::Hash[String, T.untyped])
    end
    def create_sheet_from_csv(title:, csv:, folder_id: nil, visibility: nil)
      args = { title: title, csv: csv }
      args[:folder_id]  = folder_id  if folder_id.present?
      args[:visibility] = visibility if visibility.present?
      call_tool("create_sheet_from_csv", args)
    end

    # Overwrites a block of cells in an existing spreadsheet as one version.
    # Values are typed the way typing them into a cell would be, and nil
    # clears a cell — which is how a refresh erases rows that shrank away.
    sig do
      params(document_id: Integer, values: T::Array[T::Array[T.untyped]], start: String, sheet: T.nilable(String))
        .returns(T::Hash[String, T.untyped])
    end
    def write_cells(document_id:, values:, start: "A1", sheet: nil)
      args = { id: document_id, start: start, values: values }
      args[:sheet] = sheet if sheet.present?
      call_tool("write_cells", args)
    end

    # Spreadsheets the token's user can see, most recently edited first,
    # optionally matching a title or full-text query. list_documents
    # answers every kind, so the rest are dropped here.
    sig { params(query: T.nilable(String), limit: Integer).returns(T::Array[T::Hash[String, T.untyped]]) }
    def list_spreadsheets(query: nil, limit: 50)
      args = { limit: limit }
      args[:query] = query if query.present?
      rows = call_tool("list_documents", args)
      Array(rows["result"]).grep(Hash).select { |doc| doc["kind"] == "sheet" }
    end

    # A spreadsheet's sheets (name, used range, the first row as likely
    # headers) plus its document row.
    sig { params(document_id: Integer).returns(T::Hash[String, T.untyped]) }
    def sheet_structure(document_id)
      call_tool("list_sheet_structure", { id: document_id })
    end

    # One sheet's used area as CSV text. Cells come as their stored values,
    # so a date-formatted cell reads as its serial number — the importer
    # knows to turn that back into a date.
    sig { params(document_id: Integer, sheet: T.nilable(String)).returns(String) }
    def read_sheet_csv(document_id, sheet: nil)
      args = { id: document_id, format: "csv" }
      args[:sheet] = sheet if sheet.present?
      call_tool("read_sheet", args)["content"].to_s
    end

    # The document's own page in Office, for the "Open" link.
    sig { params(document_id: Integer).returns(String) }
    def document_url(document_id)
      "#{@base_url}/d/#{document_id}"
    end

    sig { returns(String) }
    attr_reader :base_url

    private

    # Calls one MCP tool and unwraps its single JSON text block. A tool that
    # refuses answers `isError` with prose rather than a JSON-RPC error, so
    # both arms have to be checked.
    sig { params(name: String, arguments: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def call_tool(name, arguments)
      result = rpc("tools/call", { name: name, arguments: arguments })
      text   = result.dig("content", 0, "text").to_s

      raise ToolError, text.presence || "Office refused the #{name} call" if result["isError"]

      parsed = JSON.parse(text)
      parsed.is_a?(Hash) ? parsed : { "result" => parsed }
    rescue JSON::ParserError
      raise Error, "Office returned an unreadable response to #{name}"
    end

    sig { params(method_name: String, params: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def rpc(method_name, params)
      response = HttpJson.perform(
        :post, URI("#{@base_url}/mcp"),
        error: Error, label: "Office", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT,
        headers: { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json", "Accept" => "application/json" },
        body: { jsonrpc: "2.0", id: 1, method: method_name, params: params },
        network_message: ->(e) { network_message(e) }
      )
      handle(response, method_name)
    end

    sig { params(error: Exception).returns(String) }
    def network_message(error)
      return "Office at #{@base_url} did not respond in time" if error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout)

      # The host is in the message on purpose: this integration points at a
      # URL the household typed, so "which address failed" is the fix.
      Rails.logger.warn("[Office] #{error.class} reaching #{@base_url}: #{error.message}")
      "Could not reach Office at #{@base_url}"
    end

    sig { params(response: HttpJson::Response, method_name: String).returns(T::Hash[String, T.untyped]) }
    def handle(response, method_name)
      unless response.success?
        Rails.logger.warn("[Office] #{response.code} on #{method_name}: #{response.body.first(200)}")
        case response.raw
        when Net::HTTPUnauthorized, Net::HTTPForbidden
          raise Error, "Office rejected the API token"
        when Net::HTTPNotFound
          raise Error, "No MCP endpoint at #{@base_url}/mcp — check the Office URL"
        else
          raise Error, "Office returned #{response.code}"
        end
      end

      body = JSON.parse(response.body)
      # JSON-RPC puts tool failures in `result`, but transport-level
      # problems (a malformed request, an unknown method) in `error`.
      raise Error, "Office: #{body.dig('error', 'message') || 'unknown JSON-RPC error'}" if body["error"]

      result = body["result"]
      raise Error, "Office returned no result for #{method_name}" unless result.is_a?(Hash)

      result
    rescue JSON::ParserError
      raise Error, "Office returned a non-JSON response (is #{@base_url} really an Office instance?)"
    end
  end
end
