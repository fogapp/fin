require "rails_helper"

RSpec.describe Office::Client do
  let(:endpoint) { "https://office.test/mcp" }

  before { create(:office_configuration, base_url: "https://office.test/", api_key: "office_tok") }

  def tool_result(payload)
    { jsonrpc: "2.0", id: 1, result: { content: [ { type: "text", text: payload.to_json } ] } }.to_json
  end

  describe "#create_sheet_from_csv" do
    it "calls the MCP tool with a bearer token and unwraps the JSON text block" do
      stub_request(:post, endpoint)
        .with(
          headers: { "Authorization" => "Bearer office_tok", "Content-Type" => "application/json" },
          body: hash_including(
            "method" => "tools/call",
            "params" => { "name" => "create_sheet_from_csv", "arguments" => { "title" => "Transactions", "csv" => "a,b\n" } }
          )
        )
        .to_return(status: 200, body: tool_result(id: 42, title: "Transactions", sheet: "Sheet1"))

      result = described_class.new.create_sheet_from_csv(title: "Transactions", csv: "a,b\n")

      expect(result).to include("id" => 42, "sheet" => "Sheet1")
    end

    it "sends optional arguments only when present" do
      stub_request(:post, endpoint)
        .with(body: hash_including("params" => hash_including(
          "arguments" => { "title" => "T", "csv" => "x", "folder_id" => 7, "visibility" => "household" }
        )))
        .to_return(status: 200, body: tool_result(id: 1))

      described_class.new.create_sheet_from_csv(title: "T", csv: "x", folder_id: 7, visibility: "household")
    end
  end

  describe "#write_cells" do
    it "writes rows from the given anchor" do
      stub_request(:post, endpoint)
        .with(body: hash_including("params" => {
          "name" => "write_cells",
          "arguments" => { "id" => 42, "start" => "A1", "values" => [ [ "a", 1 ], [ "b", nil ] ], "sheet" => "Sheet1" }
        }))
        .to_return(status: 200, body: tool_result(range: "A1:B2"))

      result = described_class.new.write_cells(document_id: 42, values: [ [ "a", 1 ], [ "b", nil ] ], sheet: "Sheet1")

      expect(result).to eq("range" => "A1:B2")
    end
  end

  describe "#list_spreadsheets" do
    it "lists documents matching the query and keeps only spreadsheets" do
      stub_request(:post, endpoint)
        .with(body: hash_including("params" => {
          "name" => "list_documents", "arguments" => { "limit" => 50, "query" => "ledger" }
        }))
        .to_return(status: 200, body: tool_result([
          { id: 1, kind: "sheet", title: "Ledger 2019" },
          { id: 2, kind: "doc", title: "Ledger notes" }
        ]))

      expect(described_class.new.list_spreadsheets(query: "ledger")).to eq([ { "id" => 1, "kind" => "sheet", "title" => "Ledger 2019" } ])
    end
  end

  describe "#read_sheet_csv" do
    it "reads one sheet as CSV text" do
      stub_request(:post, endpoint)
        .with(body: hash_including("params" => {
          "name" => "read_sheet", "arguments" => { "id" => 9, "format" => "csv", "sheet" => "2019" }
        }))
        .to_return(status: 200, body: tool_result(sheet: "2019", content: "Date,Description,Amount\r\n46053,Rent,-1500\r\n"))

      expect(described_class.new.read_sheet_csv(9, sheet: "2019")).to eq("Date,Description,Amount\r\n46053,Rent,-1500\r\n")
    end
  end

  describe "failures" do
    it "raises ToolError with the tool's own message when a tool refuses" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { jsonrpc: "2.0", id: 1,
                result: { content: [ { type: "text", text: "You can't edit this spreadsheet" } ], isError: true } }.to_json
      )

      expect { described_class.new.write_cells(document_id: 1, values: [ [ 1 ] ]) }
        .to raise_error(Office::Client::ToolError, "You can't edit this spreadsheet")
    end

    it "names the token when Office rejects it" do
      stub_request(:post, endpoint).to_return(status: 401, body: "{}")

      expect { described_class.new.test_connection! }
        .to raise_error(Office::Client::Error, /rejected the API token/)
    end

    it "names the URL when the MCP endpoint is missing" do
      stub_request(:post, endpoint).to_return(status: 404, body: "")

      expect { described_class.new.test_connection! }
        .to raise_error(Office::Client::Error, %r{No MCP endpoint at https://office.test/mcp})
    end

    it "reports a JSON-RPC transport error" do
      stub_request(:post, endpoint).to_return(
        status: 200, body: { jsonrpc: "2.0", id: 1, error: { code: -32601, message: "Method not found" } }.to_json
      )

      expect { described_class.new.test_connection! }.to raise_error(Office::Client::Error, /Method not found/)
    end

    it "refuses to build without credentials" do
      OfficeConfiguration.destroy_all

      expect { described_class.new }.to raise_error(Office::Client::Error, /not configured/)
    end
  end

  describe "#test_connection!" do
    it "fails when the instance lacks the spreadsheet tools" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { jsonrpc: "2.0", id: 1, result: { tools: [ { name: "read_document" } ] } }.to_json
      )

      expect { described_class.new.test_connection! }
        .to raise_error(Office::Client::Error, /missing the spreadsheet tools/)
    end

    it "returns the tool names when the instance is healthy" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { jsonrpc: "2.0", id: 1,
                result: { tools: [ { name: "create_sheet_from_csv" }, { name: "write_cells" } ] } }.to_json
      )

      expect(described_class.new.test_connection!["tools"]).to include("write_cells")
    end
  end

  describe "ENV fallback" do
    it "uses OFFICE_URL and OFFICE_API_TOKEN when no row is saved" do
      OfficeConfiguration.destroy_all
      stub_const("ENV", ENV.to_h.merge("OFFICE_URL" => "https://env.test", "OFFICE_API_TOKEN" => "env_tok"))
      stub_request(:post, "https://env.test/mcp").to_return(
        status: 200,
        body: { jsonrpc: "2.0", id: 1,
                result: { tools: [ { name: "create_sheet_from_csv" }, { name: "write_cells" } ] } }.to_json
      )

      expect(described_class.new.test_connection!).to be_present
    end
  end
end
