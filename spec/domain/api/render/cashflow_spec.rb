require "rails_helper"

RSpec.describe Api::Render::Cashflow do
  def renderer = described_class.new(params: ActionController::Parameters.new)

  # top_categories/top_merchants are ranked arrays of {id:, name:, amount:, ...} now.
  def row_for(rows, name) = rows.find { |r| r[:name] == name }

  describe "#index structure" do
    it "returns all expected top-level keys" do
      result = renderer.index
      expect(result.keys).to match_array(%i[
        summary monthly_income monthly_spend monthly_spend_common
        top_categories top_categories_common
        top_merchants top_merchants_common
        top_income_sources outliers
        card_payments payment_suspects
      ])
    end

    it "returns all expected summary keys" do
      keys = renderer.index[:summary].keys
      expect(keys).to match_array(%i[
        mtd_income mtd_spend mtd_spend_common mtd_net
        lmo_income lmo_spend lmo_spend_common
        ytd_income ytd_spend ytd_spend_common ytd_net
        savings_rate_ytd
      ])
    end

    it "returns zero totals with no transactions" do
      summary = renderer.index[:summary]
      expect(summary[:mtd_income]).to eq(0.0)
      expect(summary[:ytd_spend]).to eq(0.0)
      expect(summary[:mtd_net]).to eq(0.0)
    end
  end

  describe "#index with transactions" do
    let(:merchant)  { create(:merchant) }
    let(:category)  { create(:category) }

    before do
      # CC sales this month (spend)
      create(:cash_transaction, :credit_card, :sale,
             amount: -50.0, transaction_date: Date.current,
             merchant: merchant, category: category)

      # Bank income this month (not autopay)
      create(:cash_transaction, :bank, :credit,
             amount: 2000.0, transaction_date: Date.current,
             description: "DIRECT DEPOSIT")
    end

    it "counts CC sales as spend" do
      expect(renderer.index[:summary][:mtd_spend]).to eq(50.0)
    end

    it "counts bank credits as income (excluding autopay)" do
      expect(renderer.index[:summary][:mtd_income]).to eq(2000.0)
    end

    # Exclusion is structural now (docs/credit-card-payments.md §C): a linked
    # inflow is excluded from income; an unlinked one counts no matter what
    # its description says.
    it "counts unlinked bank credits as income even with payment-shaped descriptions" do
      create(:cash_transaction, :bank, :credit,
             amount: 500.0, transaction_date: Date.current,
             description: "CREDIT CARD AUTOPAY")

      expect(renderer.index[:summary][:mtd_income]).to eq(2500.0)
    end

    it "excludes transfer-linked inflow legs from income" do
      inflow  = create(:cash_transaction, :bank, :credit,
                       amount: 500.0, transaction_date: Date.current,
                       description: "CREDIT CARD AUTOPAY")
      outflow = create(:cash_transaction, :bank, amount: -500.0,
                       account: create(:account, account_type: "Checking"),
                       transaction_date: Date.current, description: "AUTOPAY OUT")
      Transfer.create!(from_transaction_id: outflow.id, from_transaction_type: "CashTransaction",
                       to_transaction_id: inflow.id, to_transaction_type: "CashTransaction",
                       amount: 500.0).confirm!

      expect(renderer.index[:summary][:mtd_income]).to eq(2000.0)
    end

    it "populates top_categories from YTD CC sales" do
      top = renderer.index[:top_categories]
      expect(top.map { |r| r[:name] }).to include(category.name)
    end

    it "populates top_merchants from YTD CC sales" do
      top = renderer.index[:top_merchants]
      expect(top.map { |r| r[:name] }).to include(merchant.name)
    end

    it "includes large bank-sourced debits in top_categories and top_merchants" do
      create(:cash_transaction, :bank, :debit,
             amount: -28_970.0, transaction_date: Date.current,
             description: "WELLMADE DESIGN SALE", merchant: merchant, category: category)

      result = renderer.index
      expect(row_for(result[:top_categories], category.name)[:amount]).to eq(29_020.0) # 50 CC sale + 28,970 bank debit
      expect(row_for(result[:top_merchants], merchant.name)[:amount]).to eq(29_020.0)
      expect(result[:summary][:mtd_spend]).to eq(29_020.0)
    end

    it "returns savings_rate_ytd as a percentage" do
      rate = renderer.index[:summary][:savings_rate_ytd]
      expect(rate).to be_a(Float).or be_nil
      expect(rate).to be_within(1.0).of(97.5) if rate
    end

    it "builds monthly_income series with string keys" do
      series = renderer.index[:monthly_income]
      expect(series).to be_a(Hash)
      expect(series.keys.first).to be_a(String)
    end

    it "builds monthly_spend series with positive values" do
      series = renderer.index[:monthly_spend]
      expect(series.values.all? { |v| v >= 0 }).to be true
    end
  end

  describe "#index outliers" do
    let(:category) { create(:category) }

    it "flags a transaction that clears its category's Tukey fence" do
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }
      big = create(:cash_transaction, :credit_card, :sale,
                   amount: -900.0, transaction_date: Date.current, category: category)

      expect(renderer.index[:outliers].map { |o| o[:transaction_id] }).to include(big.id)
    end

    it "does not flag a category with too little history to size a fence" do
      2.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }
      create(:cash_transaction, :credit_card, :sale, amount: -900.0, transaction_date: Date.current, category: category)

      expect(renderer.index[:outliers]).to be_empty
    end

    it "does not flag transactions within a category's typical range" do
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }

      expect(renderer.index[:outliers]).to be_empty
    end

    it "flags a rare, large payment in a category too sparse to size its own fence, via the household-wide fence" do
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }
      sparse_category = create(:category, name: "Real Estate")
      big = create(:cash_transaction, :credit_card, :sale,
                   amount: -25_000.0, transaction_date: Date.current, category: sparse_category)

      expect(renderer.index[:outliers].map { |o| o[:transaction_id] }).to include(big.id)
    end

    it "flags a rare, large uncategorized payment via the household-wide fence" do
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }
      big = create(:cash_transaction, :credit_card, :sale,
                   amount: -25_000.0, transaction_date: Date.current, category: nil)

      outlier = renderer.index[:outliers].find { |o| o[:transaction_id] == big.id }
      expect(outlier).not_to be_nil
      expect(outlier[:category_name]).to eq("Uncategorized")
    end

    it "does not flag a large amount that is normal for a category with enough history" do
      rent = create(:category, name: "Rent")
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -2500.0, transaction_date: Date.current, category: rent) }

      expect(renderer.index[:outliers]).to be_empty
    end
  end

  describe "#index common totals" do
    let(:category) { create(:category) }
    let(:merchant) { create(:merchant) }

    it "excludes a flagged outlier's amount from mtd/ytd spend and category/merchant totals" do
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }
      create(:cash_transaction, :credit_card, :sale,
             amount: -900.0, transaction_date: Date.current, category: category, merchant: merchant)

      result = renderer.index
      expect(result[:summary][:mtd_spend]).to eq(result[:summary][:mtd_spend_common] + 900.0)
      expect(result[:summary][:ytd_spend]).to eq(result[:summary][:ytd_spend_common] + 900.0)
      category_row        = row_for(result[:top_categories], category.name)
      category_common_row = row_for(result[:top_categories_common], category.name)
      expect(category_row[:amount]).to eq(category_common_row[:amount] + 900.0)
      expect(category_row[:id]).to eq(category.id)
      expect(row_for(result[:top_merchants], merchant.name)[:amount]).to eq(900.0)
      expect(row_for(result[:top_merchants_common], merchant.name)).to be_nil
    end

    it "reports avg_monthly and largest alongside the total" do
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }
      create(:cash_transaction, :credit_card, :sale, amount: -900.0, transaction_date: Date.current, category: category)

      row = row_for(renderer.index[:top_categories], category.name)
      expect(row[:largest]).to eq(900.0)
      # amount (1200) / months elapsed since Jan 1 (YTD, the default window)
      months = ((Date.current.year - Date.current.beginning_of_year.year) * 12 + (Date.current.month - Date.current.beginning_of_year.month) + 1)
      expect(row[:avg_monthly]).to eq((1200.0 / months).round(2))
    end
  end

  describe "#spend_breakdown" do
    let(:category) { create(:category, name: "Groceries") }
    let(:merchant) { create(:merchant, name: "Costco") }

    # Month keys are truncated dates ("YYYY-MM-01"), matched by prefix the same
    # way the frontend normalizes them.
    def month_values(breakdown, date)
      prefix = date.strftime("%Y-%m")
      breakdown[:months].find { |k, _| k.to_s.start_with?(prefix) }&.last || {}
    end

    it "returns both dimensions, their outlier-excluded variants, and the total series" do
      expect(renderer.spend_breakdown.keys).to match_array(
        %i[from to monthly_spend monthly_spend_common category category_common merchant merchant_common]
      )
    end

    it "splits a month's spend by category, naming each series" do
      create(:cash_transaction, :credit_card, :sale, amount: -120.0, transaction_date: Date.current, category: category)

      breakdown = renderer.spend_breakdown[:category]
      expect(breakdown[:series].map { |s| s[:name] }).to eq([ "Groceries" ])
      expect(breakdown[:series].first[:id]).to eq(category.id)
      expect(month_values(breakdown, Date.current)[category.id]).to eq(120.0)
    end

    it "splits a month's spend by merchant" do
      create(:cash_transaction, :credit_card, :sale, amount: -80.0, transaction_date: Date.current, merchant: merchant)

      breakdown = renderer.spend_breakdown[:merchant]
      expect(breakdown[:series].map { |s| s[:id] }).to include(merchant.id)
      expect(month_values(breakdown, Date.current)[merchant.id]).to eq(80.0)
    end

    # The remainder is what makes a stacked month add up to the Total line, so
    # it has to absorb spend the ranked scope can't even see.
    it "puts uncategorized spend in the other bucket" do
      create(:cash_transaction, :credit_card, :sale, amount: -120.0, transaction_date: Date.current, category: category)
      create(:cash_transaction, :credit_card, :sale, amount: -30.0, transaction_date: Date.current, category: nil)

      breakdown = renderer.spend_breakdown[:category]
      expect(breakdown[:series].last).to eq({ id: "other", name: "Other" })
      expect(month_values(breakdown, Date.current)["other"]).to eq(30.0)
    end

    it "sums each month's stack to that month's total spend" do
      create(:cash_transaction, :credit_card, :sale, amount: -120.0, transaction_date: Date.current, category: category)
      create(:cash_transaction, :credit_card, :sale, amount: -30.0, transaction_date: Date.current, category: nil)

      expect(month_values(renderer.spend_breakdown[:category], Date.current).values.sum).to eq(150.0)
    end

    it "folds everything past the top 8 into the other bucket" do
      10.times do |i|
        cat = create(:category, name: "Cat #{i}")
        create(:cash_transaction, :credit_card, :sale, amount: -(100 - i), transaction_date: Date.current, category: cat)
      end

      breakdown = renderer.spend_breakdown[:category]
      # 8 ranked categories + Other; the two smallest (92 + 91) are the remainder.
      expect(breakdown[:series].size).to eq(9)
      expect(breakdown[:series].map { |s| s[:name] }.first(3)).to eq([ "Cat 0", "Cat 1", "Cat 2" ])
      expect(month_values(breakdown, Date.current)["other"]).to eq(183.0)
    end

    it "drops flagged outliers from the common variant only" do
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }
      create(:cash_transaction, :credit_card, :sale, amount: -900.0, transaction_date: Date.current, category: category)

      result = renderer.spend_breakdown
      expect(month_values(result[:category], Date.current)[category.id]).to eq(1200.0)
      expect(month_values(result[:category_common], Date.current)[category.id]).to eq(300.0)
    end

    describe "subcategories" do
      let(:home)     { create(:category, name: "Home") }
      let(:mortgage) { create(:category, name: "Mortgage", parent: home) }
      let(:dining)   { create(:category, name: "Dining Out") }

      before do
        create(:cash_transaction, :credit_card, :sale, amount: -1000.0, transaction_date: Date.current, category: mortgage)
        create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: home)
        create(:cash_transaction, :credit_card, :sale, amount: -80.0, transaction_date: Date.current, category: dining)
      end

      it "rolls them up into their parent so only top-level categories are stacked" do
        breakdown = renderer.spend_breakdown[:category]
        expect(breakdown[:series].map { |s| s[:name] }).to eq([ "Home", "Dining Out" ])
        expect(month_values(breakdown, Date.current)[home.id]).to eq(1050.0)
      end

      it "rolls them up in the ranked By Category panel too" do
        rows = renderer.index[:top_categories]
        expect(rows.map { |r| r[:name] }).to eq([ "Home", "Dining Out" ])
        expect(rows.first).to include(id: home.id, amount: 1050.0)
      end

      it "splits by subcategory when scoped to one category" do
        scoped = described_class.new(params: ActionController::Parameters.new(category_id: home.id))
        breakdown = scoped.spend_breakdown[:category]
        expect(breakdown[:series].map { |s| s[:name] }).to eq([ "Mortgage", "Home" ])
      end
    end

    it "nets a refund out of its own month rather than inflating it" do
      create(:cash_transaction, :credit_card, :sale, amount: -120.0, transaction_date: Date.current, category: category)
      create(:cash_transaction, :credit_card, :return, amount: 20.0, transaction_date: Date.current, category: category)

      expect(month_values(renderer.spend_breakdown[:category], Date.current)[category.id]).to eq(100.0)
    end

    it "returns empty series with no transactions" do
      result = renderer.spend_breakdown
      expect(result[:category][:series]).to be_empty
      expect(result[:merchant][:series]).to be_empty
    end
  end

  describe "#index monthly_spend_common" do
    let(:category) { create(:category) }

    # monthly_spend's keys come from groupdate's month truncation, not a
    # plain "YYYY-MM" string — match by prefix the same way the frontend
    # normalizes them (fillLastMonths: `key.slice(0, 7)`).
    def spend_for(hash, date)
      prefix = date.strftime("%Y-%m")
      hash.find { |k, _| k.to_s.start_with?(prefix) }&.last
    end

    it "subtracts a flagged outlier's amount from its month, leaving other months untouched" do
      6.times { create(:cash_transaction, :credit_card, :sale, amount: -50.0, transaction_date: Date.current, category: category) }
      create(:cash_transaction, :credit_card, :sale, amount: -900.0, transaction_date: Date.current, category: category)
      create(:cash_transaction, :credit_card, :sale, amount: -75.0, transaction_date: 2.months.ago, category: category)

      result = renderer.index
      expect(spend_for(result[:monthly_spend], Date.current)).to eq(spend_for(result[:monthly_spend_common], Date.current) + 900.0)
      expect(spend_for(result[:monthly_spend], 2.months.ago)).to eq(spend_for(result[:monthly_spend_common], 2.months.ago))
    end
  end
end
