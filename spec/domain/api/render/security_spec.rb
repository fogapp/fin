require "rails_helper"

RSpec.describe Api::Render::Security do
  def renderer(params = {})
    described_class.new(params: ActionController::Parameters.new(params))
  end

  describe "#index" do
    it "returns securities sorted by ticker then name" do
      create(:security, ticker: "MSFT", name: "Microsoft", watched: true)
      create(:security, ticker: "AAPL", name: "Apple", watched: true)

      result = renderer.index
      expect(result.map { |s| s[:ticker] }).to eq([ "AAPL", "MSFT" ])
    end

    it "lists only securities this household holds, watches or benchmarks against" do
      traded   = create(:security, ticker: "AAPL")
      snapshot = create(:security, ticker: "BTC")
      create(:security, ticker: "MSFT", watched: true)
      create(:security, ticker: "SPY")
      create(:investment_transaction, security: traded)
      create(:position_snapshot, security: snapshot)

      other  = create(:household, name: "Other")
      theirs = create(:security, ticker: "NVDA", watched_by: other)
      Current.set(household: other) { create(:investment_transaction, security: create(:security, ticker: "AMD")) }

      tickers = renderer.index.map { |s| s[:ticker] }
      expect(tickers).to contain_exactly("AAPL", "BTC", "MSFT", "SPY")
      expect(theirs.watched_by?(other)).to be(true)
    end
  end

  describe "#show" do
    it "includes security fields, price chart, dividends, and recent transactions" do
      security = create(:security)

      result = renderer(id: security.ticker).show
      expect(result[:id]).to eq(security.id)
      expect(result).to have_key(:price_chart)
      expect(result).to have_key(:dividends)
      expect(result).to have_key(:recent_transactions)
      expect(result[:position]).to be_nil
    end

    it "falls back to ledger cost basis when the snapshot carries none, as the portfolio does" do
      security = create(:security, ticker: "BTC")
      account  = create(:account)
      create(:investment_transaction, security: security, account: account,
             transaction_type: create(:transaction_type, :purchase), quantity: 2, amount_usd: -600)
      create(:position_snapshot, security: security, account: account, as_of_date: Date.current,
             quantity: 2, market_value: 1_000, cost_basis: 0)

      position = renderer(id: security.ticker).show[:position]
      expect(position[:cost_basis]).to eq(600.0)
      expect(position[:unrealized_gl]).to eq(400.0)
    end

    it "raises RecordNotFound for a missing id" do
      expect { renderer(id: "0").show }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#serialize" do
    it "includes expected fields" do
      security = create(:security)
      result   = renderer.serialize(security)
      expect(result.keys).to match_array(%i[id ticker name cusip security_type instrument_class display_name slug])
    end
  end
end
