require "rails_helper"

RSpec.describe Office::Datasets do
  describe ".build" do
    it "raises a helpful error for an unknown dataset" do
      expect { described_class.build("invoices", {}) }
        .to raise_error(ArgumentError, /Unknown dataset "invoices"/)
    end

    it "keeps only the params the dataset reads" do
      create(:cash_transaction)

      grid = described_class.build("transactions", { description: "AMAZON", nonsense: "x", limit: "5" })

      expect(grid.filters).to eq(description: "AMAZON")
    end
  end

  describe "transactions" do
    let(:account)  { create(:account, name: "Chase Checking") }
    let(:category) { create(:category, name: "Groceries") }

    it "builds a header plus one row per matching transaction, newest first" do
      create(:cash_transaction, description: "OLD", transaction_date: Date.current - 10, account: account)
      create(:cash_transaction, description: "NEW", transaction_date: Date.current, account: account,
                                category: category, amount: -12.5, memo: "note")

      grid = described_class.build("transactions", {})

      expect(grid.rows.first).to eq(Office::Datasets::Transactions::HEADER)
      expect(grid.rows.size).to eq(3)
      expect(grid.rows[1][2]).to eq("NEW")
      expect(grid.rows[1][4]).to eq("Groceries")
      expect(grid.rows[1][6]).to eq("Chase Checking")
      expect(grid.rows[1][7]).to eq(-12.5)
      expect(grid.rows[2][2]).to eq("OLD")
    end

    it "applies the table's filters rather than exporting everything" do
      create(:cash_transaction, description: "KEEP", account: account)
      create(:cash_transaction, description: "DROP")

      grid = described_class.build("transactions", { account_id: account.id })

      expect(grid.rows.size).to eq(2)
      expect(grid.rows[1][2]).to eq("KEEP")
    end

    it "joins tags into one cell" do
      transaction = create(:cash_transaction)
      transaction.tags << create(:tag, name: "vacation")
      transaction.tags << create(:tag, name: "reimbursable")

      grid = described_class.build("transactions", {})

      expect(grid.rows[1][10]).to eq("vacation; reimbursable")
    end

    it "names the sheet after the filters that produced it" do
      grid = described_class.build("transactions", { account_id: account.id, start_date: "2026-01-01", end_date: "2026-03-31" })

      expect(grid.title).to eq("Transactions — Chase Checking, 2026-01-01 to 2026-03-31")
    end

    it "matches the table's search box across description, merchant, category and amount" do
      merchant = create(:merchant, name: "Whole Foods")
      create(:cash_transaction, description: "WF STORE 123", merchant: merchant, amount: -88.10)
      create(:cash_transaction, description: "SHELL", amount: -88.10)

      by_merchant = described_class.build("transactions", { search: "whole" })
      by_amount   = described_class.build("transactions", { search: "88.10" })
      both_terms  = described_class.build("transactions", { search: "whole 88.10" })

      expect(by_merchant.rows.size).to eq(2)
      expect(by_amount.rows.size).to eq(3)
      expect(both_terms.rows.size).to eq(2)
    end

    it "honours the table's hidden-transfers toggle" do
      create(:cash_transaction, description: "PLAIN")
      moved = create(:cash_transaction, description: "MOVED", amount: -500)
      transfer = create(:transfer, include_in_spend: false, counterparty_account: create(:account),
                                   from_transaction_id: moved.id, from_transaction_type: "CashTransaction")
      moved.update!(transfer: transfer)

      visible = described_class.build("transactions", { show_transfers: "false" })

      expect(visible.rows.size).to eq(2)
      expect(visible.rows[1][2]).to eq("PLAIN")
      expect(described_class.build("transactions", {}).rows.size).to eq(3)
    end

    it "falls back to a plain title when nothing is filtered" do
      expect(described_class.build("transactions", {}).title).to eq("Transactions")
    end

    it "evaluates the table's own rule conditions" do
      create(:cash_transaction, description: "WHOLE FOODS", amount: -120.0)
      create(:cash_transaction, description: "SHELL", amount: -40.0)

      grid = described_class.build("transactions", {
        conditions: [ { "field" => "description", "operator" => "contains", "value" => "WHOLE" } ]
      })

      expect(grid.rows.size).to eq(2)
      expect(grid.rows[1][2]).to eq("WHOLE FOODS")
      expect(grid.title).to eq("Transactions — 1 filter")
    end

    it "stores structured conditions so a refresh replays them" do
      conditions = [ { "field" => "amount", "operator" => "less_than", "value" => "-100" } ]

      grid = described_class.build("transactions", { conditions: conditions, match_all: false })

      expect(grid.filters[:conditions]).to eq(conditions)
      expect(grid.filters[:match_all]).to be(false)
    end

    it "intersects conditions with the page's own column scope" do
      account = create(:account)
      create(:cash_transaction, description: "KEEP", account: account)
      create(:cash_transaction, description: "KEEP elsewhere")

      grid = described_class.build("transactions", {
        account_id: account.id,
        conditions: [ { "field" => "description", "operator" => "contains", "value" => "KEEP" } ]
      })

      expect(grid.rows.size).to eq(2)
      expect(grid.rows[1][2]).to eq("KEEP")
    end
  end

  describe "holdings" do
    it "rows current positions with the computed gain/loss percentage" do
      security = create(:security, ticker: "VTI", name: "Vanguard Total Market")
      account  = create(:account, name: "Brokerage")
      create(:position_snapshot, account: account, security: security, quantity: 5, price: 200.0,
                                 market_value: 1000.0, cost_basis: 800.0, unrealized_gain_loss: 200.0)

      grid = described_class.build("holdings", {})

      expect(grid.rows.first).to eq(Office::Datasets::Holdings::HEADER)
      row = grid.rows[1]
      expect(row[0]).to eq("Brokerage")
      expect(row[1]).to eq("VTI")
      expect(row[7]).to eq(1000.0)
      expect(row[10]).to eq(25.0)
    end

    it "narrows to one account and says so in the title" do
      wanted = create(:account, name: "IRA")
      create(:position_snapshot, account: wanted)
      create(:position_snapshot, account: create(:account, name: "Other"))

      grid = described_class.build("holdings", { account_id: wanted.id })

      expect(grid.rows.size).to eq(2)
      expect(grid.title).to eq("Holdings — IRA")
    end
  end

  describe "portfolio" do
    it "appends totals and performance blocks under the positions table" do
      create(:position_snapshot, market_value: 1000.0, cost_basis: 800.0, unrealized_gain_loss: 200.0)

      grid = described_class.build("portfolio", {})

      expect(grid.rows.first).to eq(Office::Datasets::Portfolio::HEADER)
      labels = grid.rows.map(&:first)
      expect(labels).to include("Totals", "Market value", "Performance", "TWR %", "XIRR %")
      # A blank row separates each block so the sheet reads as three tables.
      expect(grid.rows.count([])).to eq(2)
    end

    it "carries each position's weight in the portfolio" do
      create(:position_snapshot, security: create(:security, ticker: "AAA"), market_value: 750.0)
      create(:position_snapshot, security: create(:security, ticker: "BBB"), market_value: 250.0)

      rows = described_class.build("portfolio", {}).rows
      weights = rows[1..2].to_h { |r| [ r[0], r[7] ] }

      expect(weights).to eq("AAA" => 75.0, "BBB" => 25.0)
    end
  end

  describe "the row cap" do
    it "refuses an export larger than Office should be asked to swallow" do
      stub_const("Office::Datasets::MAX_ROWS", 1)
      create(:cash_transaction)

      expect { described_class.build("transactions", {}) }
        .to raise_error(ArgumentError, /capped at 1/)
    end
  end
end
