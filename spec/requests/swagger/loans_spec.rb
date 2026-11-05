require "swagger_helper"

RSpec.describe "Loans", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  path "/api/v1/loans" do
    get "List loans" do
      tags "Loans"
      produces "application/json"

      response "200", "loans listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/Loan" }
        before { wealth }
        run_test!
      end
    end

    post "Create a loan" do
      tags "Loans"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:                  { type: :string },
          lender:                { type: :string },
          loan_type:             { type: :string, description: "e.g. mortgage, auto, personal, student" },
          original_principal:    { type: :number },
          interest_rate:         { type: :number, description: "Annual rate as a percentage (e.g. 6.5 for 6.5%)" },
          term_months:           { type: :integer },
          start_date:            { type: :string, format: :date },
          monthly_payment:       { type: :number, description: "Full monthly payment, including any escrow" },
          escrow_property_tax:   { type: :number, description: "Monthly property tax collected into escrow" },
          escrow_insurance:      { type: :number, description: "Monthly insurance collected into escrow" },
          escrow_other:          { type: :number, description: "Other monthly escrow (e.g. PMI)" },
          status:                { type: :string, enum: %w[active paid_off] },
          notes:                 { type: :string },
          interest_only:         { type: :boolean },
          account_id:            { type: :string, format: :uuid },
          merchant_id:           { type: :string, format: :uuid },
          balance_anchor_amount: { type: :number },
          balance_anchor_date:   { type: :string, format: :date }
        },
        required: %w[name loan_type original_principal interest_rate term_months start_date]
      }

      response "201", "loan created" do
        schema "$ref" => "#/components/schemas/Loan"
        let(:body) { { name: "Home Loan", loan_type: "mortgage", original_principal: 400_000, interest_rate: 6.5, term_months: 360, start_date: "2024-01-01", status: "active" } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { {} }
        run_test!
      end
    end
  end

  path "/api/v1/loans/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Fetch a loan (includes amortisation schedule and linked transactions)" do
      tags "Loans"
      produces "application/json"

      response "200", "loan found" do
        schema "$ref" => "#/components/schemas/LoanDetail"
        let(:id) { wealth.loan.id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end

    patch "Update a loan" do
      tags "Loans"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:         { type: :string },
          status:       { type: :string },
          notes:        { type: :string },
          interest_rate: { type: :number }
        }
      }

      response "200", "loan updated" do
        schema "$ref" => "#/components/schemas/Loan"
        let(:id)   { wealth.loan.id }
        let(:body) { { notes: "Refinanced in 2024" } }
        run_test!
      end
    end

    delete "Delete a loan" do
      tags "Loans"

      response "204", "loan deleted" do
        let(:id) { create(:loan, original_principal: 50_000, interest_rate: 4.0).id }
        run_test!
      end
    end
  end

  path "/api/v1/loans/{id}/candidate_transactions" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "Cash transactions that could be loan payments" do
      tags "Loans"
      produces "application/json"
      description "Returns up to 100 transactions from the loan's linked account, excluding ones already linked to this loan."

      response "200", "candidates returned" do
        schema type: :array, items: { "$ref" => "#/components/schemas/LoanTransaction" }
        let(:id) { wealth.loan.id }
        run_test!
      end
    end
  end
end
