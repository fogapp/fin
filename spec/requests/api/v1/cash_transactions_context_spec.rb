require "rails_helper"

# GET /api/v1/cash_transactions/:id/context — the transaction page's
# explanation of one row: its peers, whether they recur, its subscription,
# how it's counted, the budget line it lands on, and the rows that might be
# its duplicate, its refund, or the rest of the same day.
RSpec.describe "Api::V1::CashTransactions#context", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }
  let(:account)      { create(:account, name: "Sapphire") }
  let(:merchant)     { create(:merchant, name: "Netflix") }
  let(:streaming)    { create(:category, name: "Streaming") }

  def charge(date, amount: -15.99, **attrs)
    create(:cash_transaction, account: account, merchant: merchant, description: "NETFLIX.COM",
           amount: amount, transaction_date: date, **attrs)
  end

  def context_for(txn)
    get "/api/v1/cash_transactions/#{txn.id}/context", headers: auth_headers
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  it "returns 401 without authentication" do
    txn = charge(Date.current)
    get "/api/v1/cash_transactions/#{txn.id}/context"
    expect(response).to have_http_status(:unauthorized)
  end

  describe "history and stats" do
    it "plots every charge at the merchant and places this one among them" do
      charge(Date.new(2026, 1, 3), amount: -10)
      charge(Date.new(2026, 2, 3), amount: -12)
      this = charge(Date.new(2026, 3, 3), amount: -30)
      charge(Date.new(2026, 4, 3), amount: -14)
      charge(Date.new(2026, 3, 9), amount: 30, transaction_type: "Return") # credits are a different series

      body = context_for(this)

      expect(body["history"]).to include("basis" => "merchant", "label" => "Netflix", "total" => 4)
      expect(body["history"]["rows"].map { |r| r["amount"] }).to eq([ -10.0, -12.0, -30.0, -14.0 ])
      expect(body["stats"]).to include("count" => 4, "ordinal" => 3, "median" => 13.0, "max" => 30.0,
                                       "percentile" => 1.0, "ratio_to_median" => 2.31)
    end

    it "falls back to near-identical descriptors when there is no merchant" do
      peer = create(:cash_transaction, description: "SQ *BLUE BOTTLE 0117", amount: -6, account: account)
      this = create(:cash_transaction, description: "SQ *BLUE BOTTLE 0042", amount: -7, account: account)

      body = context_for(this)

      expect(body["history"]["basis"]).to eq("description")
      expect(body["history"]["rows"].map { |r| r["id"] }).to contain_exactly(peer.id, this.id)
    end
  end

  describe "cadence" do
    it "detects a monthly stream the row belongs to" do
      txns = (0..5).map { |i| charge(Date.new(2026, 1, 15) >> i) }

      cadence = context_for(txns.last)["cadence"]

      expect(cadence).to include("granularity" => "month", "quantity" => 1, "includes_transaction" => true,
                                 "matched_count" => 6, "next_expected_date" => "2026-07-15")
      expect(cadence["description"]).to start_with("Monthly")
      expect(cadence["matched_ids"]).to match_array(txns.map(&:id))
    end

    it "finds none for irregular spending" do
      [ 1, 4, 20, 22, 60 ].each { |d| charge(Date.new(2026, 1, 1) + d, amount: -5) }
      this = charge(Date.new(2026, 4, 2), amount: -5)

      expect(context_for(this)["cadence"]).to be_nil
    end
  end

  it "names the subscription the row was charged against" do
    this = charge(Date.new(2026, 5, 15))
    series = create(:recurring_series, :active, merchant: merchant, name: "Netflix Premium")
    create(:recurring_occurrence, :paid, recurring_series: series, cash_transaction: this,
           expected_date: this.transaction_date, charged_date: this.transaction_date)

    expect(context_for(this)["series"]).to include("id" => series.id, "name" => "Netflix Premium",
                                                   "status" => "active", "includes_transaction" => true)
  end

  describe "treatment and budget" do
    it "reports the budget line the charge landed on and what it did to it" do
      month = Date.current.beginning_of_month
      BudgetLine.create!(category: streaming, month: month, planned: 40)
      charge(month, amount: -10, category: streaming)
      this = charge(month + 1.day, amount: -15, category: streaming)

      body = context_for(this)

      expect(body["treatment"]).to include("spend" => true, "income" => false, "budget" => true)
      expect(body["budget"]).to include("scope" => "line", "category_name" => "Streaming", "available" => 40.0,
                                        "actual" => 25.0, "before" => 10.0, "contribution" => 15.0, "remaining" => 15.0)
    end

    it "lands uncategorized spend on everything else" do
      this = charge(Date.current, amount: -20)

      expect(context_for(this)["budget"]).to include("scope" => "everything_else", "contribution" => 20.0)
    end

    it "has no budget impact when the row is excluded from budgets" do
      this = charge(Date.current, budget_excluded: true)

      body = context_for(this)
      expect(body["treatment"]).to include("spend" => true, "budget" => false)
      expect(body["budget"]).to be_nil
    end
  end

  it "flags the same charge posted twice a day apart as a possible duplicate" do
    this = charge(Date.new(2026, 6, 10))
    dup = charge(Date.new(2026, 6, 11))
    charge(Date.new(2026, 6, 20)) # outside the window
    charge(Date.new(2026, 6, 11), description: "NETFLIX GIFT CARD") # same merchant, different charge

    expect(context_for(this)["duplicates"].map { |d| d["id"] }).to eq([ dup.id ])
  end

  it "finds the refund for a charge" do
    this = charge(Date.new(2026, 6, 10), amount: -42)
    refund = charge(Date.new(2026, 6, 18), amount: 42, transaction_type: "Return")

    expect(context_for(this)["related"].first).to include("id" => refund.id, "date_diff" => 8)
  end

  it "lists the rest of the day, largest first" do
    this = charge(Date.new(2026, 6, 10))
    small = create(:cash_transaction, transaction_date: Date.new(2026, 6, 10), amount: -3, description: "COFFEE")
    big = create(:cash_transaction, transaction_date: Date.new(2026, 6, 10), amount: -300, description: "GROCER")

    same_day = context_for(this)["same_day"]
    expect(same_day["total"]).to eq(2)
    expect(same_day["rows"].map { |r| r["id"] }).to eq([ big.id, small.id ])
  end

  it "suggests the category the merchant's other charges carry" do
    3.times { |i| charge(Date.new(2026, 1, 1) + i.days, category: streaming) }
    this = charge(Date.new(2026, 2, 1))

    expect(context_for(this)["suggested_category"]).to include(
      "category_id" => streaming.id, "category_name" => "Streaming", "count" => 3, "of" => 3
    )
  end
end
