require "rails_helper"

RSpec.describe "Api::V1::Office::SheetExports", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:client)       { instance_double(Office::Client) }

  before do
    OfficeConfiguration.create!(household: token.household, base_url: "https://office.test", api_key: "t")
    allow(Office::Client).to receive(:new).and_return(client)
  end

  describe "GET /api/v1/office/sheet_exports" do
    it "returns 401 without authentication" do
      get "/api/v1/office/sheet_exports"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists the household's linked sheets, most recently exported first" do
      create(:office_sheet_export, household: token.household, dataset: "holdings", title: "Holdings",
                                   last_exported_at: 2.days.ago)
      create(:office_sheet_export, household: token.household, dataset: "transactions", title: "Transactions",
                                   last_exported_at: 1.hour.ago, row_count: 11)

      get "/api/v1/office/sheet_exports", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |e| e["title"] }).to eq([ "Transactions", "Holdings" ])
      # row_count is reported without the header row.
      expect(response.parsed_body.first).to include("row_count" => 10, "dataset_label" => "Transactions")
    end

    it "narrows to one dataset, so a table only offers its own sheets" do
      create(:office_sheet_export, household: token.household, dataset: "holdings")
      create(:office_sheet_export, household: token.household, dataset: "transactions")

      get "/api/v1/office/sheet_exports", params: { dataset: "holdings" }, headers: auth_headers

      expect(response.parsed_body.map { |e| e["dataset"] }).to eq([ "holdings" ])
    end

    it "never lists another household's sheets" do
      other = create(:household)
      create(:office_sheet_export, household: other, title: "Theirs")

      get "/api/v1/office/sheet_exports", headers: auth_headers

      expect(response.parsed_body).to be_empty
    end
  end

  describe "POST /api/v1/office/sheet_exports" do
    it "creates a spreadsheet in Office and returns the link" do
      create(:cash_transaction, description: "COFFEE")
      allow(client).to receive_messages(
        create_sheet_from_csv: { "id" => 77, "title" => "Transactions", "sheet" => "Sheet1" },
        document_url: "https://office.test/d/77"
      )

      post "/api/v1/office/sheet_exports", params: { dataset: "transactions" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "dataset" => "transactions", "document_id" => 77, "url" => "https://office.test/d/77", "row_count" => 1
      )
      expect(OfficeSheetExport.count).to eq(1)
    end

    it "passes the table's filters through to the dataset" do
      account = create(:account)
      create(:cash_transaction, account: account, description: "KEEP")
      create(:cash_transaction, description: "DROP")
      allow(client).to receive_messages(create_sheet_from_csv: { "id" => 1 }, document_url: "u")

      post "/api/v1/office/sheet_exports",
           params: { dataset: "transactions", account_id: account.id }, headers: auth_headers, as: :json

      expect(client).to have_received(:create_sheet_from_csv) do |csv:, **|
        expect(csv).to include("KEEP")
        expect(csv).not_to include("DROP")
      end
      expect(response.parsed_body["row_count"]).to eq(1)
    end

    it "stores the table's structured conditions so a refresh replays them" do
      create(:cash_transaction, description: "WHOLE FOODS")
      create(:cash_transaction, description: "SHELL")
      allow(client).to receive_messages(create_sheet_from_csv: { "id" => 2 }, document_url: "u")

      post "/api/v1/office/sheet_exports",
           params: {
             dataset: "transactions",
             conditions: [ { field: "description", operator: "contains", value: "WHOLE" } ],
             match_all: true
           },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["row_count"]).to eq(1)
      expect(response.parsed_body["filters"]).to eq(
        "conditions" => [ { "field" => "description", "operator" => "contains", "value" => "WHOLE" } ],
        "match_all" => true
      )
    end

    it "rejects a dataset that doesn't exist" do
      post "/api/v1/office/sheet_exports", params: { dataset: "payroll" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["error"]).to match(/Unknown dataset/)
    end

    it "requires a dataset" do
      post "/api/v1/office/sheet_exports", headers: auth_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "answers 502 when Office is unreachable" do
      allow(client).to receive(:create_sheet_from_csv).and_raise(Office::Client::Error, "Could not reach Office at https://office.test")

      post "/api/v1/office/sheet_exports", params: { dataset: "holdings" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["error"]).to eq("Could not reach Office at https://office.test")
    end
  end

  describe "POST /api/v1/office/sheet_exports/:id/refresh" do
    let!(:export) do
      create(:office_sheet_export, household: token.household, dataset: "holdings",
                                   document_id: 77, row_count: 5, column_count: 14, last_exported_at: 2.days.ago)
    end

    it "rewrites the linked sheet and stamps the refresh" do
      create(:position_snapshot)
      allow(client).to receive(:write_cells).and_return("range" => "A1:N2")

      post "/api/v1/office/sheet_exports/#{export.id}/refresh", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:write_cells).with(hash_including(document_id: 77, start: "A1"))
      expect(export.reload.last_exported_at).to be_within(5.seconds).of(Time.current)
    end

    it "reports an Office refusal as a 502 and records it on the sheet" do
      allow(client).to receive(:write_cells).and_raise(Office::Client::ToolError, "You can't edit this spreadsheet")

      post "/api/v1/office/sheet_exports/#{export.id}/refresh", headers: auth_headers

      expect(response).to have_http_status(:bad_gateway)
      expect(export.reload.last_error).to eq("You can't edit this spreadsheet")
    end

    it "can't refresh another household's sheet" do
      theirs = create(:office_sheet_export, household: create(:household))

      post "/api/v1/office/sheet_exports/#{theirs.id}/refresh", headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/office/sheet_exports/:id" do
    it "forgets the link without touching the spreadsheet in Office" do
      export = create(:office_sheet_export, household: token.household)

      delete "/api/v1/office/sheet_exports/#{export.id}", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(OfficeSheetExport.unscoped.where(id: export.id)).to be_empty
    end
  end
end
