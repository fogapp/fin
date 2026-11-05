require "rails_helper"

RSpec.describe "Api::V1::Budget calendar", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:year)         { Date.current.year }
  let(:jan)          { Date.new(year, 1, 1) }
  let(:feb)          { Date.new(year, 2, 1) }
  let(:mar)          { Date.new(year, 3, 1) }

  it "returns 401 without authentication" do
    get "/api/v1/budget/calendar"
    expect(response).to have_http_status(:unauthorized)
  end

  it "grids the plan in force each month, with overrides flagged and children rolled up" do
    groceries = create(:category, name: "Groceries")
    snacks    = create(:category, name: "Snacks", parent: groceries)
    account   = create(:account)
    BudgetLine.create!(category: groceries, month: jan, planned: 500)
    BudgetLine.create!(category: groceries, month: feb, planned: 550, mode: "month_only")
    # Snacks has its own line from Feb — its Jan spend rolls into Groceries.
    BudgetLine.create!(category: snacks, month: feb, planned: 50)
    create(:cash_transaction, :credit_card, :sale, account: account, category: groceries, amount: -300, transaction_date: jan + 5)
    create(:cash_transaction, :credit_card, :sale, account: account, category: snacks, amount: -40, transaction_date: jan + 6)
    create(:cash_transaction, :credit_card, :sale, account: account, category: snacks, amount: -25, transaction_date: feb + 3)

    get "/api/v1/budget/calendar", params: { year: year }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["year"]).to eq(year)
    expect(body["months"].length).to eq(12)

    groceries_row = body["rows"].find { |r| r["category_name"] == "Groceries" }
    key = ->(d) { d.strftime("%Y-%m") }
    expect(groceries_row["months"][key[jan]]).to eq("planned" => 500.0, "override" => false, "actual" => 340.0)
    expect(groceries_row["months"][key[feb]]).to eq("planned" => 550.0, "override" => true, "actual" => 0.0)
    # The Feb override doesn't carry: March is back on January's amount.
    expect(groceries_row["months"][key[mar]]).to include("planned" => 500.0, "override" => false)

    snacks_row = body["rows"].find { |r| r["category_name"] == "Snacks" }
    expect(snacks_row["months"][key[feb]]).to include("planned" => 50.0, "actual" => 25.0)
    expect(snacks_row["months"][key[mar]]).to include("planned" => 50.0)
    expect(snacks_row["months"][key[jan]]).to include("planned" => nil, "actual" => 40.0)

    expect(body["totals"][key[jan]]).to include("planned" => 500.0, "actual" => 380.0)
  end

  it "carries a yearly line as an annual amount on the row" do
    gifts = create(:category, name: "Gifts")
    BudgetLine.create!(category: gifts, month: jan, planned: 1200, period: "yearly")

    get "/api/v1/budget/calendar", params: { year: year }, headers: auth_headers

    row = response.parsed_body["rows"].sole
    expect(row).to include("period" => "yearly", "annual" => 1200.0, "total_planned" => 1200.0)
    expect(row["months"][jan.strftime("%Y-%m")]["planned"]).to be_nil
  end

  it "rejects an out-of-range year with a 400" do
    get "/api/v1/budget/calendar", params: { year: 1900 }, headers: auth_headers
    expect(response).to have_http_status(:bad_request)
  end

  it "does not include another household's lines" do
    Current.set(household: create(:household)) do
      BudgetLine.create!(category: create(:category, name: "Theirs"), month: jan, planned: 100)
    end

    get "/api/v1/budget/calendar", headers: auth_headers
    expect(response.parsed_body["rows"]).to be_empty
  end
end

RSpec.describe "Api::V1::Budget", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:month)        { Date.current.beginning_of_month }
  let(:month_str)    { month.strftime("%Y-%m") }
  let(:groceries)    { create(:category, name: "Groceries") }

  def budget(m = month_str)
    get "/api/v1/budget", params: { month: m }, headers: auth_headers
    response.parsed_body
  end

  it "sets a line that carries into later months, and stops it" do
    put "/api/v1/budget/line",
        params: { month: month_str, category_id: groceries.id, planned: 450, rollover: true },
        headers: auth_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("planned" => 450.0, "rollover" => true, "mode" => "ongoing",
                                            "set_in" => month_str)

    expect(budget["lines"].sole["category_name"]).to eq("Groceries")
    expect(budget(month.next_month.strftime("%Y-%m"))["lines"].sole["planned"]).to eq(450.0)

    delete "/api/v1/budget/line",
           params: { month: month.next_month.strftime("%Y-%m"), category_id: groceries.id },
           headers: auth_headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(budget["lines"].sole["planned"]).to eq(450.0)
    expect(budget(month.next_month.strftime("%Y-%m"))["lines"]).to be_empty
  end

  it "sets a one-month amount without changing the months after" do
    BudgetLine.create!(category: groceries, month: month.prev_month, planned: 400)

    put "/api/v1/budget/line",
        params: { month: month_str, category_id: groceries.id, planned: 900, mode: "month_only" },
        headers: auth_headers, as: :json
    expect(response.parsed_body).to include("planned" => 900.0, "mode" => "month_only")

    expect(budget["lines"].sole["planned"]).to eq(900.0)
    expect(budget(month.next_month.strftime("%Y-%m"))["lines"].sole["planned"]).to eq(400.0)
  end

  it "clears a one-month amount back to the ongoing plan" do
    BudgetLine.create!(category: groceries, month: month.prev_month, planned: 400)
    BudgetLine.create!(category: groceries, month: month, planned: 900, mode: "month_only")

    delete "/api/v1/budget/line", params: { month: month_str, category_id: groceries.id, month_only: true },
                                  headers: auth_headers, as: :json

    expect(response).to have_http_status(:no_content)
    expect(budget["lines"].sole["planned"]).to eq(400.0)
  end

  it "rejects an unknown mode" do
    put "/api/v1/budget/line",
        params: { month: month_str, category_id: groceries.id, planned: 100, mode: "bogus" },
        headers: auth_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(BudgetLine.count).to eq(0)
  end

  it "sets the income target and everything-else amount, and reports left_to_plan" do
    put "/api/v1/budget/period",
        params: { month: month_str, income_planned: 8000, other_planned: 500 },
        headers: auth_headers, as: :json
    expect(response.parsed_body).to include("income_planned" => 8000.0, "other_planned" => 500.0)
    put "/api/v1/budget/line",
        params: { month: month_str, category_id: groceries.id, planned: 450 },
        headers: auth_headers, as: :json

    body = budget
    expect(body["left_to_plan"]).to eq(7050.0)
    expect(body["everything_else"]["planned"]).to eq(500.0)
    # Both carry forward.
    expect(budget(month.next_month.strftime("%Y-%m"))["income"]["planned"]).to eq(8000.0)
  end

  it "clears a period value from this month on" do
    BudgetPeriod.create!(month: month.prev_month, other_planned: 300)

    put "/api/v1/budget/period", params: { month: month_str, other_planned: nil }, headers: auth_headers, as: :json

    expect(budget["everything_else"]["planned"]).to be_nil
    expect(budget(month.prev_month.strftime("%Y-%m"))["everything_else"]["planned"]).to eq(300.0)
  end

  it "requires a period field" do
    put "/api/v1/budget/period", params: { month: month_str }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "returns trailing planned-vs-actual history for one category" do
    account = create(:account)
    BudgetLine.create!(category: groceries, month: month.prev_month, planned: 400)
    BudgetLine.create!(category: groceries, month: month, planned: 450)
    create(:cash_transaction, :credit_card, :sale, account: account, category: groceries,
           amount: -120, transaction_date: month + 2.days)
    create(:cash_transaction, :credit_card, :sale, account: account, category: groceries,
           amount: -380, transaction_date: month.prev_month + 2.days)

    get "/api/v1/budget/line_history",
        params: { month: month_str, category_id: groceries.id, months: 3 },
        headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["category_id"]).to eq(groceries.id)
    expect(body["months"].map { |m| m["month"] }).to eq(
      [ 2, 1, 0 ].map { |i| month.months_ago(i).strftime("%Y-%m") }
    )
    expect(body["months"][0]).to include("planned" => 0.0, "actual" => 0.0)
    expect(body["months"][1]).to include("planned" => 400.0, "actual" => 380.0)
    expect(body["months"][2]).to include("planned" => 450.0, "actual" => 120.0)
  end

  it "starts a plan from the biggest categories" do
    account = create(:account)
    (1..3).each do |i|
      create(:cash_transaction, :credit_card, :sale, account: account, category: groceries,
             amount: -123, transaction_date: month.months_ago(i) + 3.days)
    end

    post "/api/v1/budget/autofill", params: { month: month_str }, headers: auth_headers, as: :json

    expect(response.parsed_body["filled"]).to eq(1)
    line = BudgetLine.sole
    expect(line.category_id).to eq(groceries.id)
    expect(line.planned).to eq(125)
    expect(line.mode).to eq(BudgetLine::Mode::Ongoing)
  end

  it "lists suggestions per category" do
    account = create(:account)
    create(:cash_transaction, :credit_card, :sale, account: account, category: groceries,
           amount: -200, transaction_date: month.prev_month + 3.days)

    get "/api/v1/budget/suggestions", params: { month: month_str }, headers: auth_headers

    row = response.parsed_body["categories"].sole
    expect(row).to include("category_name" => "Groceries", "year_total" => 200.0, "budgeted" => false)
  end

  it "rejects malformed months" do
    get "/api/v1/budget", params: { month: "julyish" }, headers: auth_headers
    expect(response).to have_http_status(:bad_request)
  end

  it "maps a lost duplicate-write race to 409 instead of 500" do
    allow(BudgetLine).to receive(:find_or_initialize_by)
      .and_raise(ActiveRecord::RecordNotUnique, "PG::UniqueViolation: duplicate key value")

    put "/api/v1/budget/line",
        params: { month: month_str, category_id: groceries.id, planned: 450 },
        headers: auth_headers, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["error"]).to match(/already exists/i)
  end
end
