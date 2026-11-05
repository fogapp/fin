require "rails_helper"

RSpec.describe Api::Render::CostBasis do
  def renderer = described_class.new(params: ActionController::Parameters.new)

  let(:account)  { create(:account) }
  let(:security) { create(:security, ticker: "AAPL", name: "Apple Inc.") }
  let(:purchase_type) { create(:transaction_type, :purchase) }
  let(:sale_type)     { create(:transaction_type, :sale) }

  describe "#index with no snapshots" do
    it "returns an empty summary and no positions" do
      result = renderer.index
      expect(result[:positions]).to eq([])
      expect(result[:summary]).to eq(
        total_positions: 0, complete: 0, partial: 0, unknown: 0,
        total_value: 0.0, known_cost_basis: 0.0
      )
    end
  end

  describe "#index with imported snapshots only (transaction-based fallback)" do
    before do
      create(:position_snapshot,
             security: security, account: account,
             as_of_date: Date.current,
             quantity: 10, market_value: 1500.0, asset_class: "Equity")
    end

    it "marks status as unknown when no purchases exist" do
      pos = renderer.index[:positions].first
      expect(pos[:status]).to eq("unknown")
      expect(pos[:computed_cost_basis]).to be_nil
      expect(pos[:unrealized_gl]).to be_nil
      expect(pos[:lots]).to eq([])
    end

    it "computes complete cost basis when purchases cover all current shares" do
      create(:investment_transaction,
             security: security, account: account,
             transaction_type: purchase_type,
             trade_date: Date.new(2026, 1, 1),
             quantity: 10, amount_usd: 1200.0, commissions_usd: 0)

      pos = renderer.index[:positions].first
      expect(pos[:bought_quantity]).to eq(10.0)
      expect(pos[:sold_quantity]).to  eq(0.0)
      expect(pos[:net_quantity]).to   eq(10.0)
      expect(pos[:gap_quantity]).to   eq(0.0)
      expect(pos[:avg_cost_per_share]).to eq(120.0)
      expect(pos[:computed_cost_basis]).to eq(1200.0)
      expect(pos[:unrealized_gl]).to eq(300.0)
      expect(pos[:status]).to eq("complete")
      expect(pos[:earliest_transaction]).to eq("2026-01-01")
      expect(pos[:transaction_count]).to eq(1)
    end

    it "marks status as partial when purchases cover only some current shares" do
      create(:investment_transaction,
             security: security, account: account,
             transaction_type: purchase_type,
             trade_date: Date.new(2026, 1, 1),
             quantity: 4, amount_usd: 400.0, commissions_usd: 0)

      pos = renderer.index[:positions].first
      expect(pos[:status]).to eq("partial")
      expect(pos[:gap_quantity]).to eq(6.0)
      expect(pos[:computed_cost_basis]).to eq(400.0)
    end

    it "includes commissions in computed cost basis" do
      create(:investment_transaction,
             security: security, account: account,
             transaction_type: purchase_type,
             quantity: 10, amount_usd: 1000.0, commissions_usd: 5.0)

      pos = renderer.index[:positions].first
      expect(pos[:avg_cost_per_share]).to eq(100.5)
    end

    it "reduces net quantity by sales but keeps status complete when net >= current" do
      create(:investment_transaction,
             security: security, account: account,
             transaction_type: purchase_type, quantity: 20, amount_usd: 2000.0, commissions_usd: 0)
      create(:investment_transaction,
             security: security, account: account,
             transaction_type: sale_type, quantity: -10, amount_usd: 1100.0, commissions_usd: 0)

      pos = renderer.index[:positions].first
      expect(pos[:sold_quantity]).to eq(10.0)
      expect(pos[:net_quantity]).to  eq(10.0)
      expect(pos[:status]).to eq("complete")
    end
  end

  describe "#index with manually-defined lots" do
    before do
      create(:position_snapshot,
             security: security, account: account,
             as_of_date: Date.current,
             quantity: 10, market_value: 1500.0, asset_class: "Equity")
    end

    it "uses lots and marks status complete when lots cover current shares" do
      create(:investment_lot,
             security: security, account: account,
             quantity: 10, cost_basis: 1200, acquired_date: Date.new(2026, 1, 1))

      pos = renderer.index[:positions].first
      expect(pos[:computed_cost_basis]).to eq(1200.0)
      expect(pos[:avg_cost_per_share]).to eq(120.0)
      expect(pos[:unrealized_gl]).to eq(300.0)
      expect(pos[:status]).to eq("complete")
      expect(pos[:lots].length).to eq(1)
      expect(pos[:lots].first).to include(quantity: 10.0, cost_basis: 1200.0)
    end

    it "calls lots complete at the same coverage the portfolio starts using them" do
      create(:investment_lot, security: security, account: account, quantity: 9.6, cost_basis: 960)

      expect(renderer.index[:positions].first[:status]).to eq("complete")
    end

    it "marks status partial when lots only cover some shares" do
      create(:investment_lot,
             security: security, account: account,
             quantity: 4, cost_basis: 400)

      pos = renderer.index[:positions].first
      expect(pos[:status]).to eq("partial")
      expect(pos[:lots].length).to eq(1)
    end
  end

  describe "#index summary aggregation" do
    it "aggregates counts and totals across positions" do
      sec2 = create(:security)
      sec3 = create(:security)

      # Complete position via lots
      create(:position_snapshot, security: security, account: account,
             as_of_date: Date.current, quantity: 10, market_value: 1500.0)
      create(:investment_lot, security: security, account: account,
             quantity: 10, cost_basis: 1200)

      # Partial position via transactions
      create(:position_snapshot, security: sec2, account: account,
             as_of_date: Date.current, quantity: 10, market_value: 500.0)
      create(:investment_transaction, security: sec2, account: account,
             transaction_type: purchase_type,
             quantity: 4, amount_usd: 400.0, commissions_usd: 0)

      # Unknown — no purchases, no lots
      create(:position_snapshot, security: sec3, account: account,
             as_of_date: Date.current, quantity: 5, market_value: 300.0)

      result = renderer.index
      expect(result[:summary][:total_positions]).to eq(3)
      expect(result[:summary][:complete]).to eq(1)
      expect(result[:summary][:partial]).to  eq(1)
      expect(result[:summary][:unknown]).to  eq(1)
      expect(result[:summary][:total_value]).to eq(2300.0)
      expect(result[:summary][:known_cost_basis]).to eq(1600.0)
    end

    it "orders positions by current_value desc" do
      sec2 = create(:security)
      create(:position_snapshot, security: security, account: account,
             as_of_date: Date.current, quantity: 1, market_value: 100.0)
      create(:position_snapshot, security: sec2, account: account,
             as_of_date: Date.current, quantity: 1, market_value: 999.0)

      tickers = renderer.index[:positions].map { |p| p[:ticker] }
      expect(tickers.first).to eq(sec2.ticker)
    end
  end
end
