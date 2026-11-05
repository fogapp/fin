require "swagger_helper"

RSpec.describe "Office", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  def configure_office!
    OfficeConfiguration.create!(household: token.household, base_url: "https://office.test", api_key: "office_tok")
  end

  # Every write goes through the MCP endpoint of the household's Office
  # instance; the docs examples stub it rather than reaching a real one.
  def stub_create_sheet(document_id: 77)
    allow(Office::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(
      create_sheet_from_csv: { "id" => document_id, "title" => "Transactions", "sheet" => "Sheet1" },
      write_cells: { "range" => "A1:M2" },
      document_url: "https://office.test/d/#{document_id}"
    )
  end

  let(:client) { instance_double(Office::Client) }

  path "/api/v1/office/configuration" do
    get "Whether this Fin can reach the household's Office instance" do
      tags "Office"
      produces "application/json"

      response "200", "configuration returned" do
        schema "$ref" => "#/components/schemas/OfficeConfiguration"
        before { configure_office! }
        run_test!
      end
    end

    patch "Save the Office URL and API token" do
      tags "Office"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          office_configuration: {
            type: :object,
            properties: {
              base_url:          { type: :string, description: "Where the Office instance is reachable" },
              api_key:           { type: :string, description: "A token minted in Office; omit to keep the saved one" },
              default_folder_id: { type: :integer, nullable: true, description: "Office folder for new spreadsheets" }
            }
          }
        }
      }

      response "200", "connection saved" do
        schema "$ref" => "#/components/schemas/OfficeConfiguration"
        let(:body) { { office_configuration: { base_url: "https://office.test", api_key: "office_tok" } } }
        run_test!
      end
    end

    delete "Remove the Office connection" do
      tags "Office"
      description "The spreadsheets stay in Office; Fin forgets the URL, the token and which sheets it made."

      response "204", "connection removed" do
        before { configure_office! }
        run_test!
      end
    end
  end

  path "/api/v1/office/configuration/test" do
    post "Test the connection to Office" do
      tags "Office"
      produces "application/json"

      response "200", "Office answered and has the spreadsheet tools" do
        schema "$ref" => "#/components/schemas/ConnectionTestResult"
        before do
          configure_office!
          stub_request(:post, "https://office.test/mcp").to_return(
            status: 200,
            body: { jsonrpc: "2.0", id: 1,
                    result: { tools: [ { name: "create_sheet_from_csv" }, { name: "write_cells" } ] } }.to_json
          )
        end
        run_test!
      end

      response "422", "Office could not be reached or refused the token" do
        schema "$ref" => "#/components/schemas/ConnectionTestResult"
        before do
          configure_office!
          stub_request(:post, "https://office.test/mcp").to_return(status: 401, body: "{}")
        end
        run_test!
      end
    end
  end

  path "/api/v1/office/sheet_exports" do
    get "List the spreadsheets linked to Fin's datatables" do
      tags "Office"
      produces "application/json"
      parameter name: :dataset, in: :query, required: false, schema: { type: :string, enum: %w[transactions holdings portfolio] },
                description: "Only the sheets built from this dataset"

      response "200", "linked sheets returned" do
        schema type: :array, items: { "$ref" => "#/components/schemas/OfficeSheetExport" }
        let(:dataset) { nil }
        before { create(:office_sheet_export, household: token.household) }
        run_test!
      end
    end

    post "Create a spreadsheet in Office from a datatable" do
      tags "Office"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          dataset:    { type: :string, enum: %w[transactions holdings portfolio] },
          visibility: { type: :string, enum: %w[private household], description: "Who in Office may see it (default private)" },
          folder_id:  { type: :integer, description: "Office folder; defaults to the configured one" },
          conditions: {
            type: :array,
            description: "The transaction table's filters (field/operator/value)",
            items: {
              type: :object,
              properties: { field: { type: :string }, operator: { type: :string }, value: { type: :string } }
            }
          },
          match_all:  { type: :boolean },
          search:     { type: :string },
          account_id: { type: :string }
        },
        required: %w[dataset]
      }

      response "201", "spreadsheet created and linked" do
        schema "$ref" => "#/components/schemas/OfficeSheetExport"
        let(:body) { { dataset: "transactions" } }
        before do
          configure_office!
          stub_create_sheet
          create(:cash_transaction)
        end
        run_test!
      end

      response "502", "Office could not be reached" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { dataset: "transactions" } }
        before do
          configure_office!
          allow(Office::Client).to receive(:new).and_return(client)
          allow(client).to receive(:create_sheet_from_csv).and_raise(Office::Client::Error, "Could not reach Office")
        end
        run_test!
      end
    end
  end

  path "/api/v1/office/sheet_exports/{id}/refresh" do
    parameter name: :id, in: :path, type: :string

    post "Rewrite a linked spreadsheet with fresh rows" do
      tags "Office"
      produces "application/json"

      response "200", "sheet refreshed" do
        schema "$ref" => "#/components/schemas/OfficeSheetExport"
        let(:id) { create(:office_sheet_export, household: token.household, dataset: "holdings").id }
        before do
          configure_office!
          stub_create_sheet
        end
        run_test!
      end
    end
  end

  path "/api/v1/office/sheet_exports/{id}" do
    parameter name: :id, in: :path, type: :string

    delete "Forget a link (the spreadsheet stays in Office)" do
      tags "Office"

      response "204", "link removed" do
        let(:id) { create(:office_sheet_export, household: token.household).id }
        run_test!
      end
    end
  end

  path "/api/v1/office/spreadsheets" do
    get "List spreadsheets in Office that could be imported" do
      tags "Office"
      produces "application/json"
      parameter name: :query, in: :query, required: false, schema: { type: :string }, description: "Title or full-text match"

      response "200", "spreadsheets listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/OfficeSpreadsheet" }
        let(:query) { "ledger" }
        before do
          configure_office!
          allow(Office::Client).to receive(:new).and_return(client)
          allow(client).to receive(:list_spreadsheets).with(query: "ledger").and_return(
            [ { "id" => 9, "kind" => "sheet", "title" => "Ledger 2019", "folder" => "Finances", "updated_at" => "2026-10-01T12:00:00Z" } ]
          )
          allow(client).to receive(:document_url).with(9).and_return("https://office.test/d/9")
        end
        run_test! do |response|
          expect(response.parsed_body.first).to include("id" => 9, "url" => "https://office.test/d/9")
        end
      end

      response "502", "Office could not be reached" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:query) { nil }
        run_test!
      end
    end
  end

  describe "reading a sheet" do
    let(:account) { create(:account, account_type: "Checking") }
    let(:sheet_csv) { "Date,Description,Amount\r\n46053,Rent,-1500\r\n46054,Coffee,oops\r\n" }

    before do
      configure_office!
      allow(Office::Client).to receive(:new).and_return(client)
      allow(client).to receive_messages(
        sheet_structure: {
          "id" => 9, "title" => "Ledger 2019", "folder" => nil, "updated_at" => "2026-10-01T12:00:00Z",
          "sheets" => [
            { "name" => "2019", "active" => true, "hidden" => false, "used_range" => "A1:C3" },
            { "name" => "Scratch", "active" => false, "hidden" => true, "used_range" => nil }
          ]
        },
        read_sheet_csv: sheet_csv
      )
      allow(client).to receive(:document_url).with(9).and_return("https://office.test/d/9")
    end

    path "/api/v1/office/spreadsheets/{id}/preview" do
      parameter name: :id, in: :path, type: :integer

      get "Check an Office sheet against the spreadsheet import layout" do
        tags "Office"
        produces "application/json"
        parameter name: :account_id, in: :query, required: false, schema: { type: :string, format: :uuid }
        parameter name: :sheet, in: :query, required: false, schema: { type: :string },
                  description: "Sheet name; defaults to the one the spreadsheet opens on"

        response "200", "sheet checked" do
          schema "$ref" => "#/components/schemas/OfficeSpreadsheetPreview"
          let(:id) { 9 }
          let(:account_id) { account.id }
          let(:sheet) { nil }
          run_test! do |response|
            body = response.parsed_body
            expect(body["sheets"].map { |s| s["name"] }).to eq([ "2019" ])
            expect(body["sheet"]).to eq("2019")
            expect(body["preview"]).to include("format" => "spreadsheet", "ready" => true, "invalid_row_count" => 1)
          end
        end
      end
    end

    path "/api/v1/office/spreadsheets/{id}/import" do
      parameter name: :id, in: :path, type: :integer

      post "Import an Office sheet's transactions into an account" do
        tags "Office"
        consumes "application/json"
        produces "application/json"
        parameter name: :body, in: :body, schema: {
          type: :object,
          properties: {
            account_id: { type: :string, format: :uuid },
            sheet:      { type: :string, description: "Sheet name; defaults to the one the spreadsheet opens on" }
          },
          required: %w[account_id]
        }

        response "201", "sheet imported" do
          schema "$ref" => "#/components/schemas/Import"
          let(:id) { 9 }
          let(:body) { { account_id: account.id, sheet: "2019" } }
          run_test! do |response|
            body = response.parsed_body
            expect(body).to include("kind" => "spreadsheet", "status" => "completed", "imported_count" => 1,
                                    "error_count" => 1, "source_filename" => "Ledger 2019 › 2019")
            expect(account.cash_transactions.sole).to have_attributes(description: "Rent", transaction_date: Date.new(2026, 1, 31))
          end
        end

        response "400", "no account given" do
          schema "$ref" => "#/components/schemas/Error"
          let(:id) { 9 }
          let(:body) { { sheet: "2019" } }
          run_test!
        end
      end
    end
  end
end
