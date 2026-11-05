require "swagger_helper"

RSpec.describe "Transfers", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  # An unconfirmed candidate pairing two accounts' opposite legs.
  let(:candidate) do
    from_txn = create(:cash_transaction, :bank, :debit, amount: -200, account: create(:account))
    to_txn   = create(:cash_transaction, :bank, :credit, amount: 200, account: create(:account), transaction_date: Date.current - 1)
    Transfer.create!(
      from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
      to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
      amount: 200, note: "Detected pair"
    )
  end

  path "/api/v1/transfers" do
    get "List transfers with both sides' details" do
      tags "Transfers"
      produces "application/json"
      description "Newest first, at most 200."
      parameter name: :confirmed, in: :query, schema: { type: :boolean }, required: false,
                description: "true = confirmed only, false = candidates only, omit = all"

      response "200", "transfers listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/TransferWithDetails" }
        before do
          candidate
          rich_cash_transaction
          create(:transfer, from_transaction_id: create(:cash_transaction, :bank, :debit).id, from_transaction_type: "CashTransaction",
                            counterparty_account_id: create(:account, kind: "external").id)
        end
        run_test! do |response|
          expect(response.parsed_body.size).to eq(3)
          expect(response.parsed_body.pluck("counterparty_account_name").compact).to be_present
        end
      end
    end

    post "Create a transfer link (a matched pair, or one side + counterparty account)" do
      tags "Transfers"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        description: "Provide both transaction sides (pair transfer), or exactly one side plus counterparty_account_id (one-sided transfer).",
        properties: {
          from_transaction_id:   { type: :string, format: :uuid },
          from_transaction_type: { type: :string, enum: %w[CashTransaction InvestmentTransaction] },
          to_transaction_id:     { type: :string, format: :uuid },
          to_transaction_type:   { type: :string, enum: %w[CashTransaction InvestmentTransaction] },
          counterparty_account_id: { type: :string, format: :uuid,
                                     description: "Account on the untracked side. Required when only one transaction side is given; must be blank when both sides are given." },
          amount:                { type: :number },
          note:                  { type: :string },
          kind:                  { type: :string, enum: %w[transfer credit_card_payment loan_payment], description: "Classified from the legs when omitted" },
          include_in_spend:      { type: :boolean },
          auto_confirm:          { type: :boolean, description: "Confirm immediately if true" }
        },
        required: %w[amount]
      }

      response "201", "transfer created" do
        schema "$ref" => "#/components/schemas/Transfer"
        let(:from_txn) { create(:cash_transaction, :bank, :debit,  amount: -500) }
        let(:to_txn)   { create(:cash_transaction, :bank, :credit, amount: 500) }
        let(:body) {
          {
            from_transaction_id:   from_txn.id,
            from_transaction_type: "CashTransaction",
            to_transaction_id:     to_txn.id,
            to_transaction_type:   "CashTransaction",
            amount: 500, note: "Savings sweep", auto_confirm: true
          }
        }
        run_test! do |response|
          expect(response.parsed_body).to include("confirmed_at" => be_present, "confirmation_source" => "user")
        end
      end
    end
  end

  path "/api/v1/transfers/candidates" do
    get "List unconfirmed (candidate) transfers detected automatically" do
      tags "Transfers"
      produces "application/json"

      response "200", "candidates listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/TransferWithDetails" }
        before { candidate }
        run_test! do |response|
          expect(response.parsed_body.first).to include("date_diff" => 1)
        end
      end
    end
  end

  path "/api/v1/transfers/for_transaction" do
    get "Find the transfer (confirmed or candidate) linked to a transaction" do
      tags "Transfers"
      produces "application/json"
      parameter name: :transaction_id,   in: :query, schema: { type: :string, format: :uuid }, required: true
      parameter name: :transaction_type, in: :query, schema: { type: :string, enum: %w[CashTransaction InvestmentTransaction] }, required: true
      let(:transaction_type) { "CashTransaction" }

      response "200", "transfer found (or null if none)" do
        schema nullable: true, allOf: [ { "$ref" => "#/components/schemas/TransferWithDetails" } ]

        context "when linked" do
          let(:transaction_id) { candidate.from_transaction_id }
          run_test! do |response|
            expect(response.parsed_body["id"]).to eq(candidate.id)
          end
        end

        context "when not linked" do
          let(:transaction_id) { create(:cash_transaction, :bank, :debit).id }
          run_test! do |response|
            expect(response.parsed_body).to be_nil
          end
        end
      end
    end
  end

  path "/api/v1/transfers/scan" do
    post "Enqueue the transfer-detection job" do
      tags "Transfers"
      produces "application/json"
      description "Scans all recent transactions asynchronously for matching debit/credit pairs and creates candidate Transfer records."

      response "202", "scan queued" do
        schema type: :object, properties: { status: { type: :string, enum: %w[queued] } }, required: %w[status]
        run_test!
      end
    end
  end

  path "/api/v1/transfers/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    patch "Edit a transfer's treatment or note" do
      tags "Transfers"
      description "The linked sides are immutable; relink by deleting and recreating."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          kind:             { type: :string, enum: %w[transfer credit_card_payment loan_payment] },
          include_in_spend: { type: :boolean },
          note:             { type: :string, nullable: true }
        }
      }

      response "200", "transfer updated" do
        schema "$ref" => "#/components/schemas/Transfer"
        let(:id)   { candidate.id }
        let(:body) { { kind: "loan_payment", include_in_spend: true } }
        run_test!
      end

      response "422", "unknown kind" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:id)   { candidate.id }
        let(:body) { { kind: "gift" } }
        run_test!
      end
    end

    delete "Delete a transfer link" do
      tags "Transfers"
      description "Removes the transfer record and clears transfer_id on both linked transactions."

      response "204", "transfer deleted" do
        let(:id) { candidate.id }
        run_test!
      end
    end
  end

  path "/api/v1/transfers/{id}/confirm" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Confirm a candidate transfer" do
      tags "Transfers"
      produces "application/json"
      description "Sets confirmed_at on the transfer and propagates transfer_id to both linked transactions."

      response "200", "transfer confirmed" do
        schema "$ref" => "#/components/schemas/Transfer"
        let(:id) { candidate.id }
        run_test!
      end
    end
  end

  path "/api/v1/transfers/{id}/dismiss" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Dismiss a candidate so detection doesn't propose it again" do
      tags "Transfers"
      produces "application/json"

      response "204", "candidate dismissed" do
        let(:id) { candidate.id }
        run_test!
      end

      response "422", "already confirmed" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { candidate.tap(&:confirm!).id }
        run_test!
      end
    end
  end
end
