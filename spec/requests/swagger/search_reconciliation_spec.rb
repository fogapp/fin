require "swagger_helper"

RSpec.describe "Search & Reconciliation", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  path "/api/v1/search" do
    get "Sitewide search" do
      tags "Search"
      produces "application/json"
      description "Up to five prefix-first matches per group. Securities are limited to those the household holds or watches."
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: "Blank returns every group empty"

      response "200", "grouped results" do
        schema "$ref" => "#/components/schemas/SearchResults"
        let(:q) { "Acme" }
        before do
          category = create(:category, name: "Acme Supplies", parent: create(:category))
          create(:merchant, name: "Acme Hardware", category: category)
          create(:tag, name: "acme-project")
          create(:account, name: "Acme Checking")
          create(:cash_transaction, description: "ACME HARDWARE #12", category: category, merchant: Merchant.first)
          create(:loan, name: "Acme Auto Loan", lender: "Acme Credit")
          security = create(:security, name: "Acme Corp", ticker: "ACME")
          create(:investment_transaction, security: security, description: "Acme Corp dividend")
        end
        run_test! do |response|
          expect(response.parsed_body.values).to all(be_present)
        end
      end
    end
  end

  path "/api/v1/reconciliation/accept" do
    post "Accept the custodian's balance for one drift finding" do
      tags "Reconciliation"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { key: { type: :string, description: "Issue key: reconciliation:<account_id>:<security_id>" } },
        required: %w[key]
      }

      response "200", "balance accepted (or nothing to do)" do
        schema "$ref" => "#/components/schemas/ReconciliationAcceptResult"
        let(:body) { { key: "reconciliation:#{create(:account).id}:#{create(:security).id}" } }
        run_test!
      end

      response "404", "unknown account or security" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) { { key: "reconciliation:0:0" } }
        run_test!
      end
    end
  end

  path "/api/v1/reconciliation/accept_all" do
    post "Accept every open drift finding in the background" do
      tags "Reconciliation"
      produces "application/json"

      response "202", "queued" do
        schema type: :object, properties: { status: { type: :string, enum: %w[queued] } }, required: %w[status]
        run_test!
      end
    end
  end
end
