require "swagger_helper"

RSpec.describe "Admin — Imports & Plaid", type: :request do
  let(:token) { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  # ── Imports ───────────────────────────────────────────────────────────────────

  path "/api/v1/imports" do
    post "Upload and run a CSV import" do
      tags "Imports"
      consumes "multipart/form-data"
      produces "application/json"
      parameter name: :file,       in: :formData, type: :file,    required: true,  description: "CSV file to import"
      parameter name: :account_id, in: :formData, type: :string, format: :uuid, required: false, description: "Pre-assign transactions to this account"
      parameter name: :broker_id,  in: :formData, type: :string, format: :uuid, required: false, description: "Associate the import with this broker"

      response "201", "import created and run" do
        schema "$ref" => "#/components/schemas/Import"
        let(:file) do
          Rack::Test::UploadedFile.new(
            StringIO.new("Date,Description,Amount\n2026-01-01,Test,-10.00"),
            "text/csv",
            original_filename: "test.csv"
          )
        end
        before { allow_any_instance_of(Importers::Dispatcher).to receive(:call) }
        run_test!
      end

      response "422", "unrecognised file format" do
        schema "$ref" => "#/components/schemas/Import"
        let(:file) do
          Rack::Test::UploadedFile.new(StringIO.new("foo,bar\n1,2"), "text/csv", original_filename: "odd.csv")
        end
        run_test! do |response|
          expect(response.parsed_body["status"]).to eq("failed")
        end
      end
    end
  end

  path "/api/v1/imports/preview" do
    post "Check a CSV without importing it" do
      tags "Imports"
      description "Reports the file's format, which spreadsheet columns it has, the rows that won't import and why, " \
                  "and how the first rows will land. Nothing is written."
      consumes "multipart/form-data"
      produces "application/json"
      parameter name: :file,       in: :formData, type: :file,   required: true,  description: "CSV file to check"
      parameter name: :account_id, in: :formData, type: :string, format: :uuid, required: false, description: "The account it would import into"

      response "200", "file checked" do
        schema "$ref" => "#/components/schemas/ImportPreview"
        let(:account_id) { create(:account).id }
        let(:file) do
          Rack::Test::UploadedFile.new(
            StringIO.new("Date,Description,Amount\n01/15/2026,Coffee,-4.50\nsoon,Tea,-3\n"),
            "text/csv",
            original_filename: "ledger.csv"
          )
        end
        run_test! do |response|
          body = response.parsed_body
          expect(body).to include("format" => "spreadsheet", "ready" => true, "invalid_row_count" => 1)
          expect(body["problems"].first["row"]).to eq(3)
          expect(CashTransaction.count).to eq(0)
        end
      end
    end
  end

  path "/api/v1/imports/spreadsheet_format" do
    get "The column layout a spreadsheet import expects" do
      tags "Imports"
      produces "application/json"

      response "200", "format described" do
        schema "$ref" => "#/components/schemas/SpreadsheetFormat"
        run_test!
      end
    end
  end

  path "/api/v1/plaid/link_token" do
    post "Create a Plaid Link token" do
      tags "Plaid"
      produces "application/json"

      response "201", "link token created" do
        schema "$ref" => "#/components/schemas/PlaidLinkToken"
        before do
          fake_client = double("PlaidClient")
          allow(PlaidClient).to receive(:new).and_return(fake_client)
          allow(fake_client).to receive(:create_link_token).and_return(double(link_token: "link-sandbox-abc"))
        end
        run_test!
      end
    end
  end

  # ── Plaid — Items ────────────────────────────────────────────────────────────

  path "/api/v1/plaid/items" do
    get "List connected institutions" do
      tags "Plaid"
      produces "application/json"

      response "200", "items listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/PlaidItem" }
        before do
          item = create(:plaid_item, last_synced_at: 1.hour.ago)
          create(:plaid_account, plaid_item: item, account: create(:account))
          create(:plaid_account, plaid_item: item, account_subtype: nil, mask: nil)
        end
        run_test!
      end
    end

    post "Connect an institution (exchange public token)" do
      tags "Plaid"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { public_token: { type: :string } },
        required: %w[public_token]
      }

      response "201", "institution connected" do
        schema "$ref" => "#/components/schemas/PlaidItem"
        before do
          fake = double("PlaidClient")
          allow(PlaidClient).to receive(:new).and_return(fake)
          allow(fake).to receive(:exchange_public_token).and_return(double(item_id: "item-1", access_token: "tok-1"))
          allow(fake).to receive(:get_item).and_return(double(item: double(institution_id: "ins_1")))
          allow(fake).to receive(:get_institution).and_return(double(institution: double(name: "Test Bank")))
          allow(fake).to receive(:get_accounts).and_return(
            double(accounts: [ double(account_id: "a1", name: "Checking", mask: "1234", type: "depository", subtype: "checking") ])
          )
        end
        let(:body) { { public_token: "public-sandbox-abc" } }
        run_test!
      end
    end
  end

  path "/api/v1/plaid/items/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Disconnect an institution" do
      tags "Plaid"

      response "204", "institution disconnected" do
        let(:id) { create(:plaid_item).id }
        run_test!
      end
    end
  end

  path "/api/v1/plaid/items/{id}/sync" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Sync an institution" do
      tags "Plaid"
      produces "application/json"

      response "202", "sync queued" do
        schema "$ref" => "#/components/schemas/Queued"
        before { allow(PlaidSyncJob).to receive(:perform_later) }
        let(:id) { create(:plaid_item).id }
        run_test!
      end
    end
  end

  # ── Plaid — Accounts ─────────────────────────────────────────────────────────

  path "/api/v1/plaid/accounts" do
    get "List Plaid accounts" do
      tags "Plaid"
      produces "application/json"

      response "200", "accounts listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/PlaidAccount" }
        before do
          create(:plaid_account, balance_current: 1250.5, balance_available: 1200, balance_currency: "USD",
                                 balance_updated_at: 1.hour.ago)
        end
        run_test!
      end
    end
  end

  path "/api/v1/plaid/accounts/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Link or unlink a Plaid account" do
      tags "Plaid"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { account_id: { type: :string, format: :uuid, nullable: true } }
      }

      response "200", "link updated" do
        schema "$ref" => "#/components/schemas/PlaidAccount"
        let(:plaid_account) { create(:plaid_account) }
        let(:id)            { plaid_account.id }
        let(:body)          { { account_id: nil } }
        run_test!
      end
    end
  end

  path "/api/v1/plaid/accounts/{id}/sync" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Sync a single Plaid account" do
      tags "Plaid"
      produces "application/json"

      response "202", "sync queued" do
        schema "$ref" => "#/components/schemas/Queued"
        before { allow(PlaidSyncJob).to receive(:perform_later) }
        let(:id) { create(:plaid_account).id }
        run_test!
      end
    end
  end
end
