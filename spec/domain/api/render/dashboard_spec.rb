require "rails_helper"

RSpec.describe Api::Render::Dashboard do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#index" do
    it "returns all expected top-level keys" do
      result = renderer.index
      expect(result.keys).to match_array(%i[
        stats portfolio_chart allocation income_series monthly_spend
        activity_chart compact_stats recent_transactions
      ])
    end

    it "includes portfolio stats with numeric values" do
      result = renderer.index
      stats = result[:stats]
      expect(stats.keys).to match_array(%i[
        portfolio_value unrealized cost_basis transactions income_ytd
      ])
      expect(stats[:portfolio_value]).to be_a(Float)
      expect(stats[:transactions]).to be_a(Integer)
    end

    it "counts investment transactions" do
      tt = create(:transaction_type, :purchase)
      create(:investment_transaction, transaction_type: tt)
      create(:investment_transaction, transaction_type: tt)

      result = renderer.index
      expect(result[:stats][:transactions]).to eq(2)
    end

    it "sums ytd income from income transaction types" do
      tt  = create(:transaction_type, :dividend)
      create(:investment_transaction, transaction_type: tt, income_usd: 100.0, trade_date: Date.current)

      result = renderer.index
      expect(result[:stats][:income_ytd]).to be_within(0.01).of(100.0)
    end

    it "reports the same monthly spend as the cashflow page" do
      month = Date.current.beginning_of_month
      create(:cash_transaction, :credit_card, :sale, amount: -30, transaction_date: month)
      create(:cash_transaction, :credit_card, :return, amount: 10, transaction_date: month)
      create(:cash_transaction, :bank, amount: -45, transaction_date: month)
      create(:cash_transaction, :credit_card, :payment, amount: 500, transaction_date: month)

      dashboard = renderer.index[:monthly_spend]
      cashflow  = Api::Render::Cashflow.new(params: ActionController::Parameters.new(from: month.to_s)).index[:monthly_spend]

      expect(dashboard[month.to_s]).to eq(65.0)
      expect(dashboard[month.to_s]).to eq(cashflow[month.to_s])
    end

    it "includes compact_stats with spend and change keys" do
      result = renderer.index
      expect(result[:compact_stats].keys).to match_array(%i[
        spend spend_change income income_change
        cc_count cc_count_change cc_avg cc_avg_change
      ])
    end

    it "filters by broker_id when provided" do
      broker1 = create(:broker)
      broker2 = create(:broker)
      acct1   = create(:account, broker: broker1)
      acct2   = create(:account, broker: broker2)
      tt      = create(:transaction_type, :purchase)
      create(:investment_transaction, transaction_type: tt, account: acct1)
      create(:investment_transaction, transaction_type: tt, account: acct2)

      result = renderer(broker_id: broker1.id).index
      expect(result[:stats][:transactions]).to eq(1)
    end

    it "charts the portfolio with the Portfolio page's engine, honoring the broker filter" do
      broker   = create(:broker)
      mine     = create(:account, broker: broker)
      other    = create(:account)
      security = create(:security, ticker: "VTI")
      purchase = create(:transaction_type, :purchase)
      day      = Date.current - 3
      [ mine, other ].each do |acct|
        create(:investment_transaction, account: acct, security: security, transaction_type: purchase,
               quantity: 10, cost_usd: 1000, trade_date: day)
        create(:position_snapshot, account: acct, security: security, as_of_date: Date.current, quantity: 10)
      end
      Candle.create!(security: security, date: day, close: 100, adjusted_close: 50,
                     currency: "USD", source: "alpha_vantage")

      all_chart    = renderer.index[:portfolio_chart]
      broker_chart = renderer(broker_id: broker.id).index[:portfolio_chart]

      # Adjusted close (a later 2:1 split), not the raw 100.
      expect(all_chart[day.to_s]).to eq(1000.0)
      expect(broker_chart[day.to_s]).to eq(500.0)
      expect(all_chart).to eq(Valuation::PortfolioSeries.call(from: day, to: Date.current))
    end

    it "returns empty portfolio_chart when no snapshots exist" do
      result = renderer.index
      expect(result[:portfolio_chart]).to eq({})
    end

    it "builds activity_chart with bucket names (colors are a client concern)" do
      tt = create(:transaction_type, :purchase)
      create(:investment_transaction, transaction_type: tt, trade_date: Date.current)

      result   = renderer.index
      buys_row = result[:activity_chart].find { |r| r[:name] == "Buys" }
      expect(buys_row).to be_present
      expect(buys_row).not_to have_key(:color)
    end
  end
end
