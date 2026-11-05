require "rails_helper"

RSpec.describe "Api::V1::Cashflow", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/cashflow" do
    it "returns 401 without authentication" do
      get "/api/v1/cashflow"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with the expected top-level keys" do
      get "/api/v1/cashflow", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "summary", "monthly_income", "monthly_spend",
        "top_categories", "top_merchants", "top_income_sources", "outliers"
      )
    end

    it "returns a summary with the expected keys" do
      get "/api/v1/cashflow", headers: auth_headers
      expect(response).to have_http_status(:ok)
      summary = response.parsed_body["summary"]
      expect(summary).to include(
        "mtd_income", "mtd_spend", "mtd_net",
        "lmo_income", "lmo_spend",
        "ytd_income", "ytd_spend", "ytd_net"
      )
    end

    it "calculates mtd_income from bank credits this month" do
      create(:cash_transaction, :bank, :credit,
             amount: 1000.00, transaction_date: Date.current)

      get "/api/v1/cashflow", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["summary"]["mtd_income"]).to eq(1000.0)
    end

    it "calculates mtd_spend from cc sales this month" do
      create(:cash_transaction, :credit_card, :sale,
             amount: -50.00, transaction_date: Date.current)

      get "/api/v1/cashflow", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["summary"]["mtd_spend"]).to eq(50.0)
    end

    it "returns mtd_net as income minus spend" do
      create(:cash_transaction, :bank, :credit, amount: 2000.00, transaction_date: Date.current)
      create(:cash_transaction, :credit_card, :sale, amount: -300.00, transaction_date: Date.current)

      get "/api/v1/cashflow", headers: auth_headers
      summary = response.parsed_body["summary"]
      expect(summary["mtd_net"]).to eq(1700.0)
    end

    it "returns monthly_income as a hash" do
      get "/api/v1/cashflow", headers: auth_headers
      expect(response.parsed_body["monthly_income"]).to be_a(Hash)
    end

    it "returns monthly_spend as a hash" do
      get "/api/v1/cashflow", headers: auth_headers
      expect(response.parsed_body["monthly_spend"]).to be_a(Hash)
    end

    it "returns top_categories as a ranked array" do
      get "/api/v1/cashflow", headers: auth_headers
      expect(response.parsed_body["top_categories"]).to be_an(Array)
    end

    it "returns top_merchants as a ranked array" do
      get "/api/v1/cashflow", headers: auth_headers
      expect(response.parsed_body["top_merchants"]).to be_an(Array)
    end

    it "returns top_income_sources as a hash" do
      get "/api/v1/cashflow", headers: auth_headers
      expect(response.parsed_body["top_income_sources"]).to be_a(Hash)
    end

    it "scopes every number to account_id when given" do
      mine   = create(:account)
      theirs = create(:account)
      create(:cash_transaction, :bank, :credit, account: mine, amount: 1000.00, transaction_date: Date.current)
      create(:cash_transaction, :bank, :credit, account: theirs, amount: 900.00, transaction_date: Date.current)

      get "/api/v1/cashflow", params: { account_id: mine.id }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["summary"]["mtd_income"]).to eq(1000.0)
    end

    it "scopes every number to tag_id when given" do
      tag = create(:tag, name: "vacation")
      tagged = create(:cash_transaction, :credit_card, :sale, amount: -75.00, transaction_date: Date.current)
      tagged.tags << tag
      create(:cash_transaction, :credit_card, :sale, amount: -500.00, transaction_date: Date.current)

      get "/api/v1/cashflow", params: { tag_id: tag.id }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["summary"]["mtd_spend"]).to eq(75.0)
    end

    it "drops rows carrying any exclude_tag_ids tag from every number" do
      vacation = create(:tag, name: "vacation")
      wedding  = create(:tag, name: "wedding")
      trip = create(:cash_transaction, :credit_card, :sale, amount: -900.00, transaction_date: Date.current)
      trip.tags << vacation
      trip.tags << wedding # two excluded tags must still drop the row once
      gift = create(:cash_transaction, :credit_card, :sale, amount: -250.00, transaction_date: Date.current)
      gift.tags << wedding
      create(:cash_transaction, :credit_card, :sale, amount: -75.00, transaction_date: Date.current)

      get "/api/v1/cashflow", params: { exclude_tag_ids: [ vacation.id, wedding.id ].join(",") }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["summary"]["mtd_spend"]).to eq(75.0)
    end

    it "scopes every number to merchant_id when given" do
      merchant = create(:merchant, name: "Rent Co")
      create(:cash_transaction, :credit_card, :sale, merchant: merchant, amount: -75.00, transaction_date: Date.current)
      create(:cash_transaction, :credit_card, :sale, amount: -500.00, transaction_date: Date.current)

      get "/api/v1/cashflow", params: { merchant_id: merchant.id }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["summary"]["mtd_spend"]).to eq(75.0)
    end

    it "scopes every number to a category's rollup when category_id is given" do
      food   = create(:category, name: "Food")
      dining = create(:category, name: "Dining", parent: food)
      create(:cash_transaction, :credit_card, :sale, amount: -80.00,  transaction_date: Date.current, category: food)
      create(:cash_transaction, :credit_card, :sale, amount: -120.00, transaction_date: Date.current, category: dining)
      create(:cash_transaction, :credit_card, :sale, amount: -500.00, transaction_date: Date.current,
             category: create(:category, name: "Travel"))

      get "/api/v1/cashflow", params: { category_id: food.id }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["summary"]["mtd_spend"]).to eq(200.0)
    end

    it "excludes transfer-linked sales from category/merchant drill-downs" do
      category = create(:category, name: "Groceries")
      merchant = create(:merchant, name: "Acme")
      txn = create(:cash_transaction, :credit_card, :sale,
                   amount: -80.00, transaction_date: Date.current,
                   category: category, merchant: merchant)
      external = create(:account, kind: "external", broker: nil, account_number: nil)
      Transfer.create!(from_transaction_id: txn.id, from_transaction_type: "CashTransaction",
                       counterparty_account_id: external.id, amount: 80.00).confirm!

      get "/api/v1/cashflow", headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["top_categories"].map { |r| r["name"] }).not_to include("Groceries")
      expect(body["top_merchants"].map { |r| r["name"] }).not_to include("Acme")
      expect(body["summary"]["mtd_spend"]).to eq(0.0)
    end
  end

  describe "GET /api/v1/cashflow/sankey" do
    it "builds an income → categories flow with drill metadata and savings" do
      account = create(:account)
      paycheck_merchant = create(:merchant, name: "Acme Payroll")
      groceries = create(:category, name: "Groceries")
      create(:cash_transaction, :bank, account: account, amount: 5000,
             description: "ACME PAYROLL", merchant: paycheck_merchant,
             transaction_date: Date.current.beginning_of_month)
      create(:cash_transaction, :credit_card, :sale, account: account, amount: -1200,
             category: groceries, transaction_date: Date.current.beginning_of_month)

      get "/api/v1/cashflow/sankey", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["totals"]).to include("income" => 5000.0, "spend" => 1200.0, "savings" => 3800.0)

      names = body["nodes"].map { |n| n["name"] }
      expect(names).to include("Acme Payroll", "Income", "Groceries", "Savings")
      grocery_node = body["nodes"].find { |n| n["name"] == "Groceries" }
      expect(grocery_node["category_id"]).to eq(groceries.id)
      expect(grocery_node["kind"]).to eq("category")

      hub = body["nodes"].index { |n| n["name"] == "Income" }
      grocery_link = body["links"].find { |l| l["target"] == names.index("Groceries") }
      expect(grocery_link).to include("source" => hub, "value" => 1200.0)
    end

    it "feeds a savings shortfall into the hub when spend exceeds income" do
      account = create(:account)
      create(:cash_transaction, :bank, account: account, amount: 3000,
             description: "PAYROLL", transaction_date: Date.current)
      create(:cash_transaction, :credit_card, :sale, account: account, amount: -4500,
             transaction_date: Date.current)

      get "/api/v1/cashflow/sankey", headers: auth_headers

      body = response.parsed_body
      expect(body["totals"]).to include("income" => 3000.0, "spend" => 4500.0, "savings" => -1500.0)
      names = body["nodes"].map { |n| n["name"] }
      expect(names).to include("From savings", "Income + savings")
      expect(names).not_to include("Income", "Savings")

      hub = names.index("Income + savings")
      shortfall = names.index("From savings")
      expect(body["nodes"][shortfall]["kind"]).to eq("shortfall")
      expect(body["links"]).to include({ "source" => shortfall, "target" => hub, "value" => 1500.0 })
      inflow  = body["links"].select { |l| l["target"] == hub }.sum { |l| l["value"] }
      outflow = body["links"].select { |l| l["source"] == hub }.sum { |l| l["value"] }
      expect(inflow).to eq(outflow)
    end

    it "folds the spend tail into Other spending with its rows as members" do
      account = create(:account)
      create(:cash_transaction, :bank, account: account, amount: 10_000,
             description: "PAYROLL", transaction_date: Date.current)
      categories = (1..10).map { |i| create(:category, name: "Cat #{i}") }
      categories.each_with_index do |category, i|
        create(:cash_transaction, :credit_card, :sale, account: account, amount: -(100 - i),
               category: category, transaction_date: Date.current)
      end

      get "/api/v1/cashflow/sankey", headers: auth_headers

      body = response.parsed_body
      other = body["nodes"].find { |n| n["name"] == "Other spending" }
      expect(other["kind"]).to eq("category")
      expect(other["members"]).to eq([
        { "name" => "Cat 9", "value" => 92.0, "category_id" => categories[8].id },
        { "name" => "Cat 10", "value" => 91.0, "category_id" => categories[9].id }
      ])
      other_link = body["links"].find { |l| l["target"] == body["nodes"].index(other) }
      expect(other_link["value"]).to eq(183.0)
      expect(body["nodes"].find { |n| n["name"] == "Cat 1" }).not_to have_key("members")
    end

    it "ships an outlier-excluded common variant alongside the full graph" do
      account = create(:account)
      groceries = create(:category, name: "Groceries")
      create(:cash_transaction, :bank, account: account, amount: 10_000,
             description: "PAYROLL", transaction_date: Date.current)
      8.times do |i|
        create(:cash_transaction, :credit_card, :sale, account: account, amount: -50,
               category: groceries, transaction_date: Date.current - i.days)
      end
      outlier = create(:cash_transaction, :credit_card, :sale, account: account, amount: -5000,
                       category: groceries, transaction_date: Date.current)

      get "/api/v1/cashflow/sankey", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["totals"]).to include("income" => 10_000.0, "spend" => 5400.0)

      common = body["common"]
      expect(common["outlier_transaction_ids"]).to eq([ outlier.id ])
      expect(common["totals"]).to include("income" => 10_000.0, "spend" => 400.0, "savings" => 9600.0)

      grocery_node = common["nodes"].find { |n| n["name"] == "Groceries" }
      expect(grocery_node).to include("kind" => "category", "category_id" => groceries.id)
      hub = common["nodes"].index { |n| n["name"] == "Income" }
      grocery_link = common["links"].find { |l| l["target"] == common["nodes"].index(grocery_node) }
      expect(grocery_link).to include("source" => hub, "value" => 400.0)
    end

    it "returns a common variant identical in totals when nothing is flagged" do
      account = create(:account)
      create(:cash_transaction, :bank, account: account, amount: 5000,
             description: "PAYROLL", transaction_date: Date.current)

      get "/api/v1/cashflow/sankey", headers: auth_headers

      body = response.parsed_body
      expect(body["common"]["outlier_transaction_ids"]).to eq([])
      expect(body["common"]["totals"]).to eq(body["totals"])
    end

    it "honors from/to bounds" do
      account = create(:account)
      create(:cash_transaction, :bank, account: account, amount: 999,
             description: "OLD INCOME", transaction_date: 2.years.ago.to_date)

      get "/api/v1/cashflow/sankey",
          params: { from: 1.month.ago.to_date.iso8601, to: Date.current.iso8601 },
          headers: auth_headers

      expect(response.parsed_body["totals"]["income"]).to eq(0.0)
    end

    it "groups the spend side by merchant when dimension=merchant" do
      account = create(:account)
      costco = create(:merchant, name: "Costco")
      create(:cash_transaction, :credit_card, :sale, account: account, amount: -300,
             merchant: costco, transaction_date: Date.current)
      create(:cash_transaction, :credit_card, :sale, account: account, amount: -100,
             transaction_date: Date.current)

      get "/api/v1/cashflow/sankey", params: { dimension: "merchant" }, headers: auth_headers

      body = response.parsed_body
      names = body["nodes"].map { |n| n["name"] }
      expect(names).to include("Costco", "No merchant")
      costco_node = body["nodes"].find { |n| n["name"] == "Costco" }
      expect(costco_node).to include("kind" => "category", "merchant_id" => costco.id)
      expect(body["totals"]["spend"]).to eq(400.0)
    end

    it "rolls subcategories into their parent when dimension=category_group" do
      account = create(:account)
      food = create(:category, name: "Food")
      dining = create(:category, name: "Dining", parent: food)
      create(:cash_transaction, :credit_card, :sale, account: account, amount: -80,
             category: food, transaction_date: Date.current)
      create(:cash_transaction, :credit_card, :sale, account: account, amount: -120,
             category: dining, transaction_date: Date.current)

      get "/api/v1/cashflow/sankey", params: { dimension: "category_group" }, headers: auth_headers

      body = response.parsed_body
      food_node = body["nodes"].find { |n| n["name"] == "Food" }
      expect(food_node["category_ids"]).to contain_exactly(food.id, dining.id)
      expect(body["nodes"].map { |n| n["name"] }).not_to include("Dining")
      food_link = body["links"].find { |l| l["target"] == body["nodes"].index(food_node) }
      expect(food_link["value"]).to eq(200.0)
    end

    it "rejects an unknown dimension with a 422" do
      get "/api/v1/cashflow/sankey", params: { dimension: "owner" }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "scopes the graph to account_id when given" do
      mine   = create(:account)
      theirs = create(:account)
      create(:cash_transaction, :bank, account: mine, amount: 3000,
             description: "MY PAYROLL", transaction_date: Date.current)
      create(:cash_transaction, :bank, account: theirs, amount: 7000,
             description: "OTHER PAYROLL", transaction_date: Date.current)

      get "/api/v1/cashflow/sankey", params: { account_id: mine.id }, headers: auth_headers

      body = response.parsed_body
      expect(body["totals"]["income"]).to eq(3000.0)
      expect(body["nodes"].map { |n| n["name"] }).not_to include("OTHER PAYROLL")
    end

    it "drops excluded-tag rows from the graph when exclude_tag_ids is given" do
      vacation = create(:tag, name: "vacation")
      create(:cash_transaction, :credit_card, :sale, amount: -60.0, transaction_date: Date.current)
      trip = create(:cash_transaction, :credit_card, :sale, amount: -800.0, transaction_date: Date.current)
      trip.tags << vacation

      get "/api/v1/cashflow/sankey", params: { exclude_tag_ids: vacation.id }, headers: auth_headers

      expect(response.parsed_body["totals"]["spend"]).to eq(60.0)
    end

    it "rejects malformed dates with a 400" do
      get "/api/v1/cashflow/sankey", params: { from: "not-a-date" }, headers: auth_headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/cashflow/spend_breakdown" do
    it "returns 401 without authentication" do
      get "/api/v1/cashflow/spend_breakdown"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with both dimensions, their common variants, and the total series" do
      get "/api/v1/cashflow/spend_breakdown", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "from", "to", "monthly_spend", "monthly_spend_common",
        "category", "category_common", "merchant", "merchant_common"
      )
      expect(response.parsed_body["category"]).to include("series", "months")
    end

    it "returns total series that reconcile with the stacks" do
      category = create(:category, name: "Groceries")
      create(:cash_transaction, :credit_card, :sale, amount: -120.0,
             transaction_date: Date.current, category: category)
      create(:cash_transaction, :credit_card, :sale, amount: -30.0,
             transaction_date: Date.current) # uncategorized → the "other" band

      get "/api/v1/cashflow/spend_breakdown",
          params: { from: Date.current.beginning_of_month.to_s, to: Date.current.to_s },
          headers: auth_headers

      body  = response.parsed_body
      month = Date.current.beginning_of_month.to_s
      expect(body["monthly_spend"][month]).to eq(150.0)
      expect(body["monthly_spend_common"][month]).to eq(150.0)
      expect(body["category"]["months"][month].values.sum).to eq(150.0)
    end

    it "drops excluded-tag rows from the totals and stacks when exclude_tag_ids is given" do
      vacation = create(:tag, name: "vacation")
      category = create(:category, name: "Travel")
      create(:cash_transaction, :credit_card, :sale, amount: -40.0, transaction_date: Date.current, category: category)
      trip = create(:cash_transaction, :credit_card, :sale, amount: -700.0, transaction_date: Date.current, category: category)
      trip.tags << vacation

      get "/api/v1/cashflow/spend_breakdown",
          params: { from: Date.current.beginning_of_month.to_s, to: Date.current.to_s, exclude_tag_ids: vacation.id },
          headers: auth_headers

      body  = response.parsed_body
      month = Date.current.beginning_of_month.to_s
      expect(body["monthly_spend"][month]).to eq(40.0)
      expect(body["category"]["months"][month].values.sum).to eq(40.0)
    end

    it "scopes the breakdown to a category's rollup when category_id is given" do
      food   = create(:category, name: "Food")
      dining = create(:category, name: "Dining", parent: food)
      create(:cash_transaction, :credit_card, :sale, amount: -80.0,  transaction_date: Date.current, category: food)
      create(:cash_transaction, :credit_card, :sale, amount: -120.0, transaction_date: Date.current, category: dining)
      create(:cash_transaction, :credit_card, :sale, amount: -500.0, transaction_date: Date.current,
             category: create(:category, name: "Travel"))

      get "/api/v1/cashflow/spend_breakdown",
          params: { category_id: food.id, from: Date.current.beginning_of_month.to_s, to: Date.current.to_s },
          headers: auth_headers

      body = response.parsed_body
      expect(body["monthly_spend"].values.sum).to eq(200.0)
      expect(body["category"]["series"].map { |s| s["name"] }).to contain_exactly("Food", "Dining")
    end

    it "splits spend by category within the requested window" do
      category = create(:category, name: "Groceries")
      create(:cash_transaction, :credit_card, :sale, amount: -120.0,
             transaction_date: Date.current, category: category)

      get "/api/v1/cashflow/spend_breakdown",
          params: { from: Date.current.beginning_of_month.to_s, to: Date.current.to_s },
          headers: auth_headers

      body = response.parsed_body["category"]
      expect(body["series"]).to eq([ { "id" => category.id, "name" => "Groceries" } ])
      expect(body["months"].values.first[category.id]).to eq(120.0)
    end

    it "does not count another household's transactions" do
      Current.set(household: create(:household)) do
        create(:cash_transaction, :credit_card, :sale, amount: -500.0,
               transaction_date: Date.current, category: create(:category, name: "Theirs"))
      end

      get "/api/v1/cashflow/spend_breakdown", headers: auth_headers

      expect(response.parsed_body["category"]["series"]).to be_empty
    end
  end

  describe "GET /api/v1/cashflow/activity" do
    it "returns 401 without authentication" do
      get "/api/v1/cashflow/activity"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns a dense 30-day series ending today, with zero-filled gaps" do
      get "/api/v1/cashflow/activity", headers: auth_headers

      expect(response).to have_http_status(:ok)
      days = response.parsed_body["days"]
      expect(days.length).to eq(30)
      expect(days.first["date"]).to eq((Date.current - 29.days).to_s)
      expect(days.last["date"]).to eq(Date.current.to_s)
      expect(days.map { |d| d["spend"] }.uniq).to eq([ 0.0 ])
    end

    it "reports spend as a positive number on the day it happened" do
      account = create(:account)
      create(:cash_transaction, :bank, account: account, amount: -42.5,
             description: "GROCERY", transaction_date: Date.current - 2)

      get "/api/v1/cashflow/activity", headers: auth_headers

      day = response.parsed_body["days"].find { |d| d["date"] == (Date.current - 2).to_s }
      expect(day["spend"]).to eq(42.5)
      expect(response.parsed_body["total_spend"]).to eq(42.5)
    end

    it "totals income and nets it against spend" do
      account = create(:account)
      create(:cash_transaction, :bank, account: account, amount: 1000,
             description: "PAYCHECK", transaction_date: Date.current - 1)
      create(:cash_transaction, :bank, account: account, amount: -250,
             description: "RENT", transaction_date: Date.current - 1)

      get "/api/v1/cashflow/activity", headers: auth_headers

      body = response.parsed_body
      expect(body["total_income"]).to eq(1000.0)
      expect(body["total_spend"]).to eq(250.0)
      expect(body["net"]).to eq(750.0)
    end

    it "excludes activity older than the 30-day window" do
      account = create(:account)
      create(:cash_transaction, :bank, account: account, amount: -500,
             description: "ANCIENT", transaction_date: Date.current - 90)

      get "/api/v1/cashflow/activity", headers: auth_headers

      expect(response.parsed_body["total_spend"]).to eq(0.0)
    end

    it "does not count another household's transactions" do
      Current.set(household: create(:household)) do
        create(:cash_transaction, :bank, account: create(:account), amount: -777,
               description: "THEIRS", transaction_date: Date.current)
      end

      get "/api/v1/cashflow/activity", headers: auth_headers

      expect(response.parsed_body["total_spend"]).to eq(0.0)
    end
  end
end
