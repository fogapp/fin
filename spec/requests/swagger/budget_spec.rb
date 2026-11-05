require "swagger_helper"

RSpec.describe "Budget", type: :request do
  include WealthFixture

  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }
  let(:wealth)        { build_wealth_fixture }
  let(:month)         { Date.current.strftime("%Y-%m") }

  path "/api/v1/budget" do
    get "A month's budget from the standing plan, with actuals, rollover and forecast" do
      tags "Budget"
      produces "application/json"
      parameter name: :month, in: :query, type: :string, required: false, description: "YYYY-MM (default: this month)"

      response "200", "budget month" do
        schema "$ref" => "#/components/schemas/BudgetData"
        before { wealth }
        run_test!
      end

      response "400", "malformed month" do
        schema "$ref" => "#/components/schemas/Error"
        let(:month) { "13/2026" }
        run_test!
      end
    end
  end

  path "/api/v1/budget/calendar" do
    get "Planned vs actual per category for every month of a year" do
      tags "Budget"
      produces "application/json"
      parameter name: :year, in: :query, type: :integer, required: false, description: "Default: this year"

      response "200", "budget calendar" do
        schema "$ref" => "#/components/schemas/BudgetCalendarData"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/budget/line_history" do
    get "One category's planned and actual over recent months" do
      tags "Budget"
      produces "application/json"
      parameter name: :category_id, in: :query, type: :string, format: :uuid, required: true
      parameter name: :month,       in: :query, type: :string, required: false, description: "YYYY-MM ending month (default: this month)"
      parameter name: :months,      in: :query, type: :integer, required: false, description: "Months of history (1–12, default 6)"

      response "200", "line history" do
        schema "$ref" => "#/components/schemas/BudgetLineHistory"
        let(:category_id) { wealth.groceries.id }
        run_test!
      end
    end
  end

  path "/api/v1/budget/suggestions" do
    get "Typical spend per category, for setting budget amounts" do
      tags "Budget"
      produces "application/json"
      parameter name: :month, in: :query, type: :string, required: false, description: "YYYY-MM (default: this month)"

      response "200", "suggestions" do
        schema "$ref" => "#/components/schemas/BudgetSuggestions"
        before { wealth }
        run_test!
      end
    end
  end

  path "/api/v1/budget/line" do
    put "Set a category's budget from a month on, or for that month only" do
      tags "Budget"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          category_id: { type: :string, format: :uuid },
          month:       { type: :string, description: "YYYY-MM" },
          planned:     { type: :number },
          rollover:    { type: :boolean },
          period:      { type: :string, enum: %w[monthly yearly], description: "A yearly planned is an annual amount" },
          mode:        { type: :string, enum: %w[ongoing month_only], description: "ongoing (default): from this month on" }
        },
        required: %w[category_id month]
      }

      response "200", "budget line" do
        schema "$ref" => "#/components/schemas/BudgetLine"
        let(:body) { { category_id: wealth.dining.id, month: month, planned: 250, rollover: true } }
        run_test!
      end
    end

    delete "Stop budgeting a category from a month on" do
      tags "Budget"
      consumes "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          category_id: { type: :string, format: :uuid },
          month:       { type: :string, description: "YYYY-MM" },
          month_only:  { type: :boolean, description: "Only drop this month's one-month amount" }
        },
        required: %w[category_id month]
      }

      response "204", "line removed" do
        let(:body) { { category_id: wealth.dining.id, month: month } }
        run_test!
      end
    end
  end

  path "/api/v1/budget/period" do
    put "Set the income target and/or the everything-else amount from a month on" do
      tags "Budget"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          month:          { type: :string, description: "YYYY-MM" },
          income_planned: { type: :number, nullable: true },
          other_planned:  { type: :number, nullable: true, description: "Budget for spend outside budgeted categories" }
        },
        required: %w[month]
      }

      response "200", "period saved" do
        schema "$ref" => "#/components/schemas/BudgetPeriod"
        let(:body) { { month: month, income_planned: 7_000, other_planned: 800 } }
        run_test!
      end
    end
  end

  path "/api/v1/budget/autofill" do
    post "Start a plan: the few categories that make up most spending, plus everything else" do
      tags "Budget"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { month: { type: :string, description: "YYYY-MM" } },
        required: %w[month]
      }

      response "200", "lines filled" do
        schema "$ref" => "#/components/schemas/BudgetAutofillResult"
        let(:body) { wealth && { month: Date.current.next_month.strftime("%Y-%m") } }
        run_test!
      end
    end
  end
end
