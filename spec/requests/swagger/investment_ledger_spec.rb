require "swagger_helper"

RSpec.describe "Investment ledger", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  # ── Account balances & holdings ───────────────────────────────────────────────

  path "/api/v1/accounts/{account_id}/balance_snapshots" do
    parameter name: :account_id, in: :path, type: :string, format: :uuid, required: true

    get "Daily balance history for an account" do
      tags "Accounts"
      produces "application/json"
      parameter name: :from, in: :query, schema: { type: :string, format: :date }, required: false, description: "Default: one year ago"
      parameter name: :to,   in: :query, schema: { type: :string, format: :date }, required: false

      response "200", "balance history returned" do
        schema type: :array, items: { "$ref" => "#/components/schemas/AccountBalancePoint" }
        let(:account) { create(:account) }
        let(:account_id) { account.id }
        before { AccountBalanceSnapshot.record(account, balance: 1500, source: AccountBalanceSnapshot::Source::Manual) }
        run_test! do |response|
          expect(response.parsed_body).to be_present
        end
      end

      response "400", "malformed date" do
        schema "$ref" => "#/components/schemas/Error"
        let(:account_id) { create(:account).id }
        let(:from) { "not-a-date" }
        run_test!
      end
    end
  end

  path "/api/v1/accounts/{id}/holdings" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Current investment holdings for an account" do
      tags "Accounts"
      produces "application/json"

      response "200", "holdings returned" do
        schema "$ref" => "#/components/schemas/AccountHoldings"
        let(:snapshot) { create(:position_snapshot) }
        let(:id) { snapshot.account_id }
        before { create(:security_label, security: snapshot.security) }
        run_test! do |response|
          expect(response.parsed_body["positions"].first["security_label"]).to be_present
        end
      end
    end
  end

  # ── Investment lots ───────────────────────────────────────────────────────────

  path "/api/v1/investment_lots" do
    get "List a security's tax lots" do
      tags "Investment Lots"
      produces "application/json"
      parameter name: :security_id, in: :query, schema: { type: :string, format: :uuid }, required: true

      response "200", "lots listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/InvestmentLot" }
        let(:security_id) { create(:investment_lot, notes: "DRIP").security_id }
        run_test! do |response|
          expect(response.parsed_body).to be_present
        end
      end
    end

    post "Create an investment lot" do
      tags "Investment Lots"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          security_id:   { type: :string, format: :uuid },
          account_id:    { type: :string, format: :uuid, nullable: true },
          acquired_date: { type: :string, format: :date, nullable: true },
          quantity:      { type: :number },
          cost_basis:    { type: :number },
          notes:         { type: :string, nullable: true }
        },
        required: %w[security_id quantity cost_basis]
      }

      response "201", "lot created" do
        schema "$ref" => "#/components/schemas/InvestmentLot"
        let(:body) { { security_id: create(:security).id, account_id: create(:account).id, quantity: 10, cost_basis: 1000, acquired_date: Date.current.to_s } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { security_id: create(:security).id } }
        run_test!
      end
    end
  end

  path "/api/v1/investment_lots/generate" do
    post "Auto-generate lots from investment transactions" do
      tags "Investment Lots"
      consumes "application/json"
      produces "application/json"
      description <<~DESC
        Previews or commits FIFO lots derived from buy/sell transactions.
        Pass `commit: true` to persist. Committing over existing lots needs
        `replace: true`, otherwise it answers 409 with the existing count.
      DESC
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          security_id: { type: :string, format: :uuid },
          commit:      { type: :boolean, description: "Persist the generated lots (default: preview only)" },
          replace:     { type: :boolean, description: "Replace existing lots when committing" }
        },
        required: %w[security_id]
      }
      let(:purchase) { rich_investment_transaction }

      response "200", "preview of lots to generate" do
        schema type: :array, items: { "$ref" => "#/components/schemas/InvestmentLotPreview" }
        let(:body) { { security_id: purchase.security_id } }
        run_test! do |response|
          expect(response.parsed_body).to be_present
        end
      end

      response "201", "lots committed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/InvestmentLot" }
        let(:body) { { security_id: purchase.security_id, commit: true, replace: true } }
        run_test! do |response|
          expect(response.parsed_body).to be_present
        end
      end

      response "409", "lots already exist" do
        schema type: :object,
               properties: { error: { type: :string, enum: %w[lots_exist] }, count: { type: :integer } },
               required: %w[error count]
        before     { create(:investment_lot, security: purchase.security) }
        let(:body) { { security_id: purchase.security_id, commit: true } }
        run_test!
      end
    end
  end

  path "/api/v1/investment_lots/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Update an investment lot" do
      tags "Investment Lots"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          account_id:    { type: :string, format: :uuid, nullable: true },
          acquired_date: { type: :string, format: :date, nullable: true },
          quantity:      { type: :number },
          cost_basis:    { type: :number },
          notes:         { type: :string, nullable: true }
        }
      }

      response "200", "lot updated" do
        schema "$ref" => "#/components/schemas/InvestmentLot"
        let(:id)   { create(:investment_lot).id }
        let(:body) { { notes: "Adjusted for DRIP" } }
        run_test!
      end
    end

    delete "Delete an investment lot" do
      tags "Investment Lots"

      response "204", "lot deleted" do
        let(:id) { create(:investment_lot).id }
        run_test!
      end
    end
  end

  # ── Investment transactions ───────────────────────────────────────────────────

  path "/api/v1/investment_transactions" do
    get "List investment transactions" do
      tags "Investment Transactions"
      produces "application/json"
      description "Newest first."
      parameter name: :account_id,  in: :query, schema: { type: :string, format: :uuid }, required: false
      parameter name: :security_id, in: :query, schema: { type: :string, format: :uuid }, required: false
      parameter name: :limit,       in: :query, required: false,
                schema: { oneOf: [ { type: :integer, minimum: 1, maximum: 2000 }, { type: :string, enum: %w[all] } ] },
                description: "Max results (default 200); `all` returns the whole ledger, capped at 10,000"
      parameter name: :offset,      in: :query, schema: { type: :integer, minimum: 0 }, required: false

      response "200", "transactions listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/InvestmentTransaction" }
        before { rich_investment_transaction }
        let(:limit) { "all" }
        run_test! do |response|
          expect(response.parsed_body).to be_present
        end
      end
    end

    post "Create an investment transaction manually" do
      tags "Investment Transactions"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          account_id:       { type: :string, format: :uuid },
          security_id:      { type: :string, format: :uuid },
          transaction_type: { type: :string, description: "A transaction-type category (e.g. Purchase, Sale, Dividend)" },
          trade_date:       { type: :string, format: :date },
          quantity:         { type: :number },
          price_usd:        { type: :number },
          amount_usd:       { type: :number },
          description:      { type: :string }
        },
        required: %w[account_id transaction_type trade_date]
      }

      response "201", "transaction created" do
        schema "$ref" => "#/components/schemas/InvestmentTransaction"
        let(:body) {
          {
            account_id:       create(:account).id,
            security_id:      create(:security).id,
            transaction_type: create(:transaction_type, :purchase).category,
            trade_date:       Date.current.to_s,
            quantity:         10,
            price_usd:        150.0,
            amount_usd:       -1500.0,
            description:      "Manual buy"
          }
        }
        run_test!
      end

      response "404", "unknown transaction type" do
        schema "$ref" => "#/components/schemas/Error"
        let(:body) { { account_id: create(:account).id, transaction_type: "Nope", trade_date: Date.current.to_s } }
        run_test!
      end
    end
  end

  path "/api/v1/investment_transactions/{id}/reprocess" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Recalculate the position snapshot for this transaction" do
      tags "Investment Transactions"
      produces "application/json"

      response "200", "position recalculated, or skipped for non-trade rows" do
        schema "$ref" => "#/components/schemas/InvestmentTransactionReprocess"

        context "for a purchase" do
          let(:id) { rich_investment_transaction.id }
          run_test! do |response|
            expect(response.parsed_body["status"]).to eq("updated")
          end
        end

        context "for a dividend" do
          let(:id) { create(:investment_transaction, transaction_type: create(:transaction_type, :dividend)).id }
          run_test! do |response|
            expect(response.parsed_body["status"]).to eq("skipped")
          end
        end
      end
    end
  end
end
