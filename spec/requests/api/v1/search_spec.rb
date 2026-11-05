require "rails_helper"

RSpec.describe "Api::V1::Search", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/search" do
    it "returns 401 without authentication" do
      get "/api/v1/search", params: { q: "coffee" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns empty groups for a blank query" do
      get "/api/v1/search", params: { q: "" }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      %w[merchants categories tags accounts transactions loans investment_transactions securities].each do |key|
        expect(body[key]).to eq([])
      end
    end

    it "matches merchants, ranking a prefix match before a substring-only match" do
      prefix_match    = create(:merchant, name: "Whole Foods")
      substring_match = create(:merchant, name: "The Whole Truth")
      create(:merchant, name: "Amazon")

      get "/api/v1/search", params: { q: "whole" }, headers: auth_headers
      names = response.parsed_body["merchants"].map { |m| m["name"] }
      expect(names).to eq([ prefix_match.name, substring_match.name ])
    end

    it "matches categories and includes the parent name for a subcategory" do
      parent = create(:category, name: "Food")
      child  = create(:category, name: "Coffee Shops", parent: parent)

      get "/api/v1/search", params: { q: "coffee" }, headers: auth_headers
      row = response.parsed_body["categories"].first
      expect(row["id"]).to eq(child.id)
      expect(row["parent_name"]).to eq("Food")
    end

    it "matches tags" do
      tag = create(:tag, name: "Hawaii 2026")
      get "/api/v1/search", params: { q: "hawaii" }, headers: auth_headers
      expect(response.parsed_body["tags"].map { |t| t["id"] }).to eq([ tag.id ])
    end

    it "matches accounts" do
      account = create(:account, name: "Chase Sapphire")
      get "/api/v1/search", params: { q: "sapphire" }, headers: auth_headers
      expect(response.parsed_body["accounts"].map { |a| a["id"] }).to eq([ account.id ])
    end

    it "matches transactions by description or memo, with merchant/category context" do
      merchant = create(:merchant, name: "Whole Foods")
      category = create(:category, name: "Groceries")
      by_description = create(:cash_transaction, :bank, description: "WHOLEFDS MKT",
                              merchant: merchant, category: category)
      by_memo = create(:cash_transaction, :bank, description: "POS PURCHASE", memo: "wholefoods run")

      get "/api/v1/search", params: { q: "wholef" }, headers: auth_headers
      ids = response.parsed_body["transactions"].map { |t| t["id"] }
      expect(ids).to contain_exactly(by_description.id, by_memo.id)

      row = response.parsed_body["transactions"].find { |t| t["id"] == by_description.id }
      expect(row["merchant_name"]).to eq("Whole Foods")
      expect(row["category_name"]).to eq("Groceries")
    end

    it "matches loans by name or lender" do
      by_name   = create(:loan, name: "Home Mortgage", lender: "Chase")
      by_lender = create(:loan, name: "Auto Loan", lender: "Chase Bank")

      get "/api/v1/search", params: { q: "chase" }, headers: auth_headers
      expect(response.parsed_body["loans"].map { |l| l["id"] }).to contain_exactly(by_name.id, by_lender.id)
    end

    it "matches investment transactions and includes the security's ticker" do
      security = create(:security, ticker: "AAPL", name: "Apple Inc")
      txn = create(:investment_transaction, security: security, description: "AAPL BUY")

      get "/api/v1/search", params: { q: "aapl buy" }, headers: auth_headers
      row = response.parsed_body["investment_transactions"].first
      expect(row["id"]).to eq(txn.id)
      expect(row["security_ticker"]).to eq("AAPL")
    end

    describe "securities" do
      it "matches a security the household holds via an investment transaction" do
        security = create(:security, ticker: "AAPL", name: "Apple Inc")
        create(:investment_transaction, security: security)

        get "/api/v1/search", params: { q: "apple" }, headers: auth_headers
        expect(response.parsed_body["securities"].map { |s| s["id"] }).to eq([ security.id ])
      end

      it "matches a security the household watches but doesn't hold" do
        security = create(:security, ticker: "TSLA", name: "Tesla Inc", watched: true)

        get "/api/v1/search", params: { q: "tesla" }, headers: auth_headers
        expect(response.parsed_body["securities"].map { |s| s["id"] }).to eq([ security.id ])
      end

      it "never returns a security this household neither holds nor watches, even on a matching query" do
        create(:security, ticker: "NVDA", name: "Nvidia Corp")

        get "/api/v1/search", params: { q: "nvidia" }, headers: auth_headers
        expect(response.parsed_body["securities"]).to eq([])
      end

      it "never leaks another household's held/watched security into this household's results" do
        other_household = create(:household)
        other_user       = create(:user)
        create(:household_membership, user: other_user, household: other_household)

        security = Current.set(household: other_household) do
          s = create(:security, ticker: "MSFT", name: "Microsoft Corp")
          create(:investment_transaction, security: s)
          s
        end

        get "/api/v1/search", params: { q: "microsoft" }, headers: auth_headers
        expect(response.parsed_body["securities"]).to eq([])

        other_token = create(:api_token, user: other_user, household: other_household)
        get "/api/v1/search", params: { q: "microsoft" },
            headers: { "Authorization" => "Bearer #{other_token.raw_token}" }
        expect(response.parsed_body["securities"].map { |s| s["id"] }).to eq([ security.id ])
      end
    end

    describe "household isolation" do
      it "never returns another household's merchants, transactions, or loans" do
        other_household = create(:household)
        other_user      = create(:user)
        create(:household_membership, user: other_user, household: other_household)

        Current.set(household: other_household) do
          create(:merchant, name: "Costco Wholesale")
          create(:loan, name: "Costco Card Loan", lender: "Citi")
          create(:cash_transaction, :bank, description: "COSTCO WHSE")
        end

        get "/api/v1/search", params: { q: "costco" }, headers: auth_headers
        body = response.parsed_body
        expect(body["merchants"]).to eq([])
        expect(body["loans"]).to eq([])
        expect(body["transactions"]).to eq([])
      end
    end
  end
end
