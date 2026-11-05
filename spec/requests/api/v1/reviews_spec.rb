require "rails_helper"

RSpec.describe "Api::V1::Reviews", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:last_month)   { Date.current.prev_month.beginning_of_month }

  it "returns 401 without authentication" do
    get "/api/v1/review"
    expect(response).to have_http_status(:unauthorized)
  end

  it "summarizes the requested month's cashflow, rankings, and biggest transactions" do
    account = create(:account)
    groceries = create(:category, name: "Groceries")
    costco = create(:merchant, name: "Costco")
    create(:cash_transaction, :bank, :credit, account: account, amount: 6000, transaction_date: last_month + 3)
    create(:cash_transaction, :credit_card, :sale, account: account, amount: -900,
           category: groceries, merchant: costco, transaction_date: last_month + 5)
    # Prior month for the deltas
    create(:cash_transaction, :bank, :credit, account: account, amount: 5000,
           transaction_date: last_month.prev_month + 2)

    get "/api/v1/review", params: { month: last_month.strftime("%Y-%m") }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["month"]).to eq(last_month.strftime("%Y-%m"))
    expect(body["cashflow"]).to include(
      "income" => 6000.0, "spend" => 900.0, "net" => 5100.0,
      "prev_income" => 5000.0, "savings_rate" => 85.0
    )
    expect(body["top_categories"].first).to include("name" => "Groceries", "amount" => 900.0)
    expect(body["top_merchants"].first).to include("name" => "Costco", "amount" => 900.0)
    expect(body["largest_transactions"].first).to include("description" => "Costco", "amount" => 900.0)
    expect(body["budget"]).to include("planned", "actual", "remaining")
    expect(body["subscriptions"]).to include("paid_count" => 0, "paid_total" => 0.0)
  end

  it "ranks subcategory spend under its parent category" do
    home = create(:category, name: "Home")
    mortgage = create(:category, name: "Mortgage", parent: home)
    dining = create(:category, name: "Dining Out")
    create(:cash_transaction, :credit_card, :sale, amount: -1000, category: mortgage, transaction_date: last_month + 1)
    create(:cash_transaction, :credit_card, :sale, amount: -50, category: home, transaction_date: last_month + 2)
    create(:cash_transaction, :credit_card, :sale, amount: -80, category: dining, transaction_date: last_month + 3)

    get "/api/v1/review", params: { month: last_month.strftime("%Y-%m") }, headers: auth_headers

    expect(response.parsed_body["top_categories"]).to match([
      include("id" => home.id, "name" => "Home", "amount" => 1050.0),
      include("name" => "Dining Out", "amount" => 80.0)
    ])
  end

  it "reads net worth from the metric points at each month boundary" do
    create(:metric_point, metric_key: "net_worth", date: last_month.prev_month.end_of_month, value: 100_000)
    create(:metric_point, metric_key: "net_worth", date: last_month.end_of_month, value: 104_500)

    get "/api/v1/review", params: { month: last_month.strftime("%Y-%m") }, headers: auth_headers

    expect(response.parsed_body["net_worth"]).to eq(
      "ending" => 104_500.0, "starting" => 100_000.0, "change" => 4_500.0
    )
  end

  it "defaults to the previous month" do
    get "/api/v1/review", headers: auth_headers
    expect(response.parsed_body["month"]).to eq(last_month.strftime("%Y-%m"))
  end

  it "rejects a malformed month with a 400" do
    get "/api/v1/review", params: { month: "julyish" }, headers: auth_headers
    expect(response).to have_http_status(:bad_request)
  end

  it "does not count another household's transactions" do
    Current.set(household: create(:household)) do
      create(:cash_transaction, :bank, :credit, account: create(:account),
             amount: 9999, transaction_date: last_month + 1)
    end

    get "/api/v1/review", params: { month: last_month.strftime("%Y-%m") }, headers: auth_headers
    expect(response.parsed_body["cashflow"]["income"]).to eq(0.0)
  end
end
