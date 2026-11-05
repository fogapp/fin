require "swagger_helper"

RSpec.describe "Cashflow", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }

  # The scope every cashflow view accepts; omitted params mean "everything".
  def self.scope_parameters
    parameter name: :from,            in: :query, type: :string, required: false, description: "ISO start date (inclusive)"
    parameter name: :to,              in: :query, type: :string, required: false, description: "ISO end date (inclusive)"
    parameter name: :account_id,      in: :query, type: :string, required: false
    parameter name: :tag_id,          in: :query, type: :string, required: false
    parameter name: :exclude_tag_ids, in: :query, type: :string, required: false, description: "Comma-separated tag ids to leave out"
    parameter name: :category_id,     in: :query, type: :string, required: false
    parameter name: :merchant_id,     in: :query, type: :string, required: false
  end

  path "/api/v1/cashflow" do
    get "Cashflow overview: income, spend, rankings and outliers" do
      tags "Cashflow"
      produces "application/json"
      scope_parameters

      response "200", "cashflow data" do
        schema "$ref" => "#/components/schemas/CashflowData"
        before { wealth }
        run_test!
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end
  end

  path "/api/v1/cashflow/spend_breakdown" do
    get "Monthly spend split by category and by merchant" do
      tags "Cashflow"
      produces "application/json"
      scope_parameters

      response "200", "spend breakdown" do
        schema "$ref" => "#/components/schemas/SpendBreakdownData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/cashflow/sankey" do
    get "Money-flow graph from income sources to spend" do
      tags "Cashflow"
      produces "application/json"
      description "Carries both the as-it-happened graph and the outlier-excluded (`common`) variant."
      scope_parameters
      parameter name: :dimension, in: :query, required: false,
                schema: { type: :string, enum: %w[category category_group merchant] }

      response "200", "sankey graph" do
        schema "$ref" => "#/components/schemas/CashflowSankeyData"
        before { wealth }
        run_test!
      end

      response "422", "unknown dimension" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:dimension) { "planet" }
        run_test!
      end
    end
  end

  path "/api/v1/cashflow/activity" do
    get "Daily spend and income for the activity heatmap" do
      tags "Cashflow"
      produces "application/json"

      response "200", "activity days" do
        schema "$ref" => "#/components/schemas/ActivityData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/review" do
    get "Monthly review" do
      tags "Cashflow"
      produces "application/json"
      parameter name: :month, in: :query, type: :string, required: false, description: "YYYY-MM (default: last month)"

      response "200", "the month's review" do
        schema "$ref" => "#/components/schemas/ReviewData"
        let(:month) { Date.current.prev_month.strftime("%Y-%m") }
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/saved_reports" do
    get "List saved chart-page reports" do
      tags "Cashflow"
      produces "application/json"

      response "200", "saved reports" do
        schema type: :array, items: { "$ref" => "#/components/schemas/SavedReport" }
        before { wealth }
        run_test!
      end
    end

    post "Save a report" do
      tags "Cashflow"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          name:   { type: :string },
          config: { "$ref" => "#/components/schemas/SavedReportConfig" }
        },
        required: %w[name config]
      }

      response "201", "report saved" do
        schema "$ref" => "#/components/schemas/SavedReport"
        let(:body) { { name: "Dining YTD", config: { section: "spending", preset: "ytd", hash: "#spending" } } }
        run_test!
      end
    end
  end

  path "/api/v1/saved_reports/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    delete "Delete a saved report" do
      tags "Cashflow"

      response "204", "report deleted" do
        let(:id) { SavedReport.create!(name: "Old", config: { section: "income" }.to_json).id }
        run_test!
      end
    end
  end
end
