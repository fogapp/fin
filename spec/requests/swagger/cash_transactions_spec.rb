require "swagger_helper"

RSpec.describe "Cash Transactions", type: :request do
  let(:token) { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  let(:transaction_ref) { { "$ref" => "#/components/schemas/CashTransaction" } }

  path "/api/v1/cash_transactions" do
    get "List cash transactions" do
      tags "Cash Transactions"
      produces "application/json"
      description "Newest first. Windowed with limit/offset; an omitted limit serves at most 1,000 rows."
      parameter name: :source,           in: :query, schema: { type: :string, enum: %w[bank credit_card] }, required: false, description: "Filter by source"
      parameter name: :merchant_id,      in: :query, schema: { type: :string, format: :uuid }, required: false
      parameter name: :category_id,      in: :query, schema: { type: :string, format: :uuid }, required: false, description: "Includes the category's subcategories"
      parameter name: :category_ids,     in: :query, schema: { type: :string }, required: false, description: "Comma-separated exact category ids (no rollup); wins over category_id"
      parameter name: :account_id,       in: :query, schema: { type: :string, format: :uuid }, required: false
      parameter name: :loan_id,          in: :query, schema: { type: :string, format: :uuid }, required: false
      parameter name: :tag_id,           in: :query, schema: { type: :string, format: :uuid }, required: false
      parameter name: :exclude_tag_ids,  in: :query, schema: { type: :string }, required: false, description: "Comma-separated tag ids to leave out"
      parameter name: :transaction_type, in: :query, schema: { type: :string }, required: false
      parameter name: :description,      in: :query, schema: { type: :string }, required: false, description: "Case-insensitive substring match"
      parameter name: :start_date,       in: :query, schema: { type: :string, format: :date }, required: false, description: "Inclusive lower bound on transaction_date (alias: from)"
      parameter name: :end_date,         in: :query, schema: { type: :string, format: :date }, required: false, description: "Inclusive upper bound on transaction_date (alias: to)"
      parameter name: :limit,            in: :query, schema: { type: :integer, minimum: 1, maximum: 1000 }, required: false
      parameter name: :offset,           in: :query, schema: { type: :integer, minimum: 0 }, required: false

      response "200", "transactions listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/CashTransaction" }
        before { rich_cash_transaction }
        run_test! do |response|
          expect(response.parsed_body).not_to be_empty
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end

    post "Create a cash transaction" do
      tags "Cash Transactions"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          source:           { type: :string, enum: %w[bank credit_card] },
          transaction_date: { type: :string, format: :date },
          post_date:        { type: :string, format: :date },
          description:      { type: :string },
          amount:           { type: :number },
          transaction_type: { type: :string },
          source_row_hash:  { type: :string },
          category_id:      { type: :string, format: :uuid },
          merchant_id:      { type: :string, format: :uuid },
          account_id:       { type: :string, format: :uuid },
          loan_id:          { type: :string, format: :uuid },
          balance:          { type: :number },
          memo:             { type: :string }
        },
        required: %w[source transaction_date amount source_row_hash]
      }

      response "201", "transaction created" do
        schema "$ref" => "#/components/schemas/CashTransaction"
        let(:body) { { source: "bank", transaction_date: Date.current, description: "Paycheck", amount: 1000.0, transaction_type: "Credit", source_row_hash: "swagger-test-#{SecureRandom.hex(4)}", balance: 2000.0 } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { source: "bank" } }
        run_test!
      end
    end
  end

  path "/api/v1/cash_transactions/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Fetch a cash transaction" do
      tags "Cash Transactions"
      produces "application/json"

      response "200", "transaction found" do
        schema "$ref" => "#/components/schemas/CashTransaction"
        let(:id) { rich_cash_transaction.id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { 0 }
        run_test!
      end
    end

    patch "Update a cash transaction" do
      tags "Cash Transactions"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          description:      { type: :string },
          amount:           { type: :number },
          transaction_date: { type: :string, format: :date },
          transaction_type: { type: :string },
          memo:             { type: :string, nullable: true },
          category_id:      { type: :string, format: :uuid, nullable: true },
          merchant_id:      { type: :string, format: :uuid, nullable: true },
          account_id:       { type: :string, format: :uuid, nullable: true },
          loan_id:          { type: :string, format: :uuid, nullable: true }
        }
      }

      response "200", "transaction updated" do
        schema "$ref" => "#/components/schemas/CashTransaction"
        let(:id) { rich_cash_transaction.id }
        let(:body) { { memo: "updated note" } }
        run_test!
      end
    end

    delete "Delete a cash transaction" do
      tags "Cash Transactions"

      response "204", "transaction deleted" do
        let(:id) { create(:cash_transaction, :bank, :debit).id }
        let(:body) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/cash_transactions/filter" do
    post "Filter cash transactions by a condition set" do
      tags "Cash Transactions"
      description "The workflow editor's condition preview. Returns a bare array, or {transactions, total} when `count` is set."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          conditions: {
            type: :array,
            items: {
              type: :object,
              properties: { field: { type: :string }, operator: { type: :string }, value: { type: :string } },
              required: %w[field operator]
            }
          },
          match_all:  { type: :boolean },
          limit:      { type: :integer, minimum: 1, maximum: 1000 },
          count:      { type: :boolean, description: "Also return the full match count" }
        },
        required: %w[conditions]
      }

      response "200", "filtered transactions" do
        schema oneOf: [
          { type: :array, items: { "$ref" => "#/components/schemas/CashTransaction" } },
          { "$ref" => "#/components/schemas/CashTransactionFilterCount" }
        ]
        before { rich_cash_transaction }

        context "without count" do
          let(:body) { { conditions: [ { field: "description", operator: "contains", value: "ACH" } ], match_all: true } }
          run_test! do |response|
            expect(response.parsed_body).to be_an(Array).and(be_present)
          end
        end

        context "with count" do
          let(:body) { { conditions: [ { field: "description", operator: "contains", value: "ACH" } ], match_all: true, limit: 8, count: true } }
          run_test! do |response|
            expect(response.parsed_body).to include("total" => be_positive)
          end
        end
      end
    end
  end

  path "/api/v1/cash_transactions/{id}/add_tag" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Add a tag to a transaction" do
      tags "Cash Transactions"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { tag_id: { type: :string, format: :uuid } },
        required: %w[tag_id]
      }

      response "200", "tag added" do
        schema "$ref" => "#/components/schemas/CashTransaction"
        let(:id)   { rich_cash_transaction.id }
        let(:body) { { tag_id: create(:tag).id } }
        run_test!
      end
    end
  end

  path "/api/v1/cash_transactions/{id}/remove_tag" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Remove a tag from a transaction" do
      tags "Cash Transactions"
      produces "application/json"
      parameter name: :tag_id, in: :query, schema: { type: :string, format: :uuid }, required: true

      response "200", "tag removed" do
        schema "$ref" => "#/components/schemas/CashTransaction"
        let(:txn)    { rich_cash_transaction }
        let(:id)     { txn.id }
        let(:tag_id) { txn.tags.first.id }
        run_test!
      end
    end
  end

  path "/api/v1/cash_transactions/{id}/similar" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Transactions with the same or a similar description" do
      tags "Cash Transactions"
      produces "application/json"
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 50 }, required: false

      response "200", "similar transactions" do
        schema "$ref" => "#/components/schemas/SimilarTransactions"
        let(:id) { create(:cash_transaction, description: "SQ *CAFE 0042", account: create(:account)).id }
        before do
          create(:cash_transaction, description: "SQ *CAFE 0042", account: create(:account))
          create(:cash_transaction, description: "SQ *CAFE 0117", account: create(:account))
        end
        run_test! do |response|
          expect(response.parsed_body["transactions"]).to be_present
        end
      end
    end
  end

  path "/api/v1/cash_transactions/{id}/context" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Context for the transaction page: history, cadence, subscription, budget impact, nearby rows" do
      tags "Cash Transactions"
      produces "application/json"

      response "200", "transaction context" do
        schema "$ref" => "#/components/schemas/TransactionContext"
        let(:merchant) { create(:merchant) }
        let(:account)  { create(:account) }
        let(:id) do
          (0..3).map do |i|
            create(:cash_transaction, merchant: merchant, account: account, amount: -15.99,
                   transaction_date: Date.current.beginning_of_month << (3 - i))
          end.last.id
        end
        run_test! do |response|
          expect(response.parsed_body["cadence"]).to include("granularity" => "month")
          expect(response.parsed_body["budget"]).to include("scope" => "everything_else")
        end
      end
    end
  end

  path "/api/v1/cash_transactions/transfer_search" do
    get "Candidate counterparts for manually linking a transfer" do
      tags "Cash Transactions"
      produces "application/json"
      parameter name: :transaction_id, in: :query, schema: { type: :string, format: :uuid }, required: true
      parameter name: :days, in: :query, schema: { type: :integer, minimum: 1, maximum: 30 }, required: false, description: "Search window either side (default 14)"

      response "200", "candidates ranked by amount then date" do
        schema type: :array, items: { "$ref" => "#/components/schemas/TransferSearchResult" }
        let(:source_txn) { create(:cash_transaction, :bank, :debit, account: create(:account)) }
        let(:transaction_id) { source_txn.id }
        before { create(:cash_transaction, :bank, :credit, amount: 75.0, account: create(:account), transaction_date: Date.current - 1) }
        run_test! do |response|
          expect(response.parsed_body).to be_present
        end
      end
    end
  end

  path "/api/v1/cash_transactions/bulk_update" do
    post "Bulk update transactions" do
      tags "Cash Transactions"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          ids:         { type: :array, items: { type: :string, format: :uuid }, description: "Transaction IDs to update" },
          account_id:  { type: :string, format: :uuid, description: "Assign this account to all IDs" },
          merchant_id: { type: :string, format: :uuid, description: "Assign this merchant to all IDs" },
          category_id: { type: :string, format: :uuid, description: "Assign this category to all IDs" },
          tag_ids:     { type: :array, items: { type: :string, format: :uuid }, description: "Add these tags to all IDs" }
        },
        required: %w[ids]
      }

      response "200", "bulk update applied" do
        schema "$ref" => "#/components/schemas/CashTransactionBulkUpdate"
        let(:txn)  { create(:cash_transaction, :bank, :debit) }
        let(:body) { { ids: [ txn.id ], category_id: create(:category).id, tag_ids: [ create(:tag).id ] } }
        run_test!
      end

      response "400", "ids missing" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) { {} }
        run_test!
      end
    end
  end
end
