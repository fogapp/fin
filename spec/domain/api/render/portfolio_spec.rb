require "rails_helper"

RSpec.describe Api::Render::Portfolio do
  def renderer = described_class.new(params: ActionController::Parameters.new)

  describe "#index with no data" do
    it "returns the expected top-level keys" do
      result = renderer.index
      expect(result.keys).to match_array(%i[as_of_date summary by_asset_class portfolio_history positions])
    end

    it "returns empty positions when no snapshots exist" do
      expect(renderer.index[:positions]).to eq([])
    end

    it "returns zero summary totals when no snapshots exist" do
      summary = renderer.index[:summary]
      expect(summary[:total_value]).to eq(0.0)
      expect(summary[:total_cost_basis]).to eq(0.0)
      expect(summary[:unrealized_gl]).to eq(0.0)
    end
  end

  describe "#index with data" do
    let(:security) { create(:security, ticker: "AAPL", name: "Apple Inc.") }
    let(:account)  { create(:account) }

    before do
      create(:position_snapshot,
             security: security, account: account,
             as_of_date: Date.current,
             quantity: 10, price: 150.0,
             market_value: 1500.0, cost_basis: 1200.0,
             unrealized_gain_loss: 300.0, asset_class: "Equity")
    end

    it "consolidates positions by security" do
      result = renderer.index
      expect(result[:positions].length).to eq(1)
      pos = result[:positions].first
      expect(pos[:security_ticker]).to eq("AAPL")
      expect(pos[:market_value]).to eq(1500.0)
      expect(pos[:cost_basis]).to eq(1200.0)
    end

    it "sums market_value across multiple accounts for the same security" do
      account2 = create(:account)
      create(:position_snapshot,
             security: security, account: account2,
             as_of_date: Date.current,
             quantity: 5, price: 150.0,
             market_value: 750.0, cost_basis: 600.0,
             unrealized_gain_loss: 150.0, asset_class: "Equity")

      result = renderer.index
      expect(result[:positions].length).to eq(1)
      expect(result[:positions].first[:market_value]).to eq(2250.0)
      expect(result[:positions].first[:quantity]).to eq(15.0)
    end

    it "computes correct summary totals" do
      summary = renderer.index[:summary]
      expect(summary[:total_value]).to eq(1500.0)
      expect(summary[:total_cost_basis]).to eq(1200.0)
      expect(summary[:unrealized_gl]).to eq(300.0)
    end

    it "groups by_asset_class" do
      create(:position_snapshot,
             security: create(:security), account: account,
             as_of_date: Date.current,
             market_value: 500.0, asset_class: "Fixed Income")

      by_class = renderer.index[:by_asset_class]
      expect(by_class["Equity"]).to eq(1500.0)
      expect(by_class["Fixed Income"]).to eq(500.0)
    end

    it "calculates unrealized_gl_pct" do
      pos = renderer.index[:positions].first
      expect(pos[:unrealized_gl_pct]).to eq(25.0)
    end

    it "only returns the latest as_of_date snapshot" do
      security2 = create(:security)
      create(:position_snapshot, security: security2, account: account,
             as_of_date: 1.day.ago.to_date, market_value: 999.0)

      result = renderer.index
      expect(result[:positions].none? { |p| p[:security_ticker] == security2.ticker }).to be true
    end
  end
end
