require "rails_helper"

# Custodian closes are stored as quoted (bonds per 100 of face); the
# valuation engine must apply the quoting scale to them exactly once.
RSpec.describe "Valuing custodian-priced bonds" do
  let(:account) { create(:account) }
  let(:bond)    { create(:security, :without_ticker, name: "Pomona Ca Unif Sch Dist 5% 08/01/35", instrument_class: "bond") }
  let(:today)   { Date.current }

  before do
    MarketData::CustodianPrices.write!(bond, [ { date: today - 10, close: BigDecimal("101") },
                                               { date: today, close: BigDecimal("100") } ])
  end

  context "with a held position" do
    before do
      create(:position_snapshot, account: account, security: bond, as_of_date: today,
                                 quantity: 25_000, price: 100, market_value: 25_000)
    end

    it "scales per-100 closes to dollars in PortfolioSeries.call_by_account" do
      series = Valuation::PortfolioSeries.call_by_account(from: today - 10, to: today, account_ids: [ account.id ])[account.id]
      expect(series[today - 10]).to be_within(0.01).of(25_250)
      expect(series[today]).to be_within(0.01).of(25_000)
    end
  end

  context "once the bond is sold and its snapshot reads 0" do
    before do
      bond.update!(instrument_attributes: { Security::QUOTE_BASIS_KEY => Security::QUOTE_BASIS_PER_HUNDRED })
      create(:investment_transaction, account: account, security: bond, trade_date: today - 60, quantity: 25_000,
                                      transaction_type: create(:transaction_type, :purchase))
      create(:investment_transaction, account: account, security: bond, trade_date: today - 1, quantity: 25_000,
                                      transaction_type: create(:transaction_type, :sale))
      create(:position_snapshot, account: account, security: bond, as_of_date: today,
                                 quantity: 0, price: 100, market_value: 0)
    end

    it "keeps the per-100 scale from the security" do
      series = Valuation::PortfolioSeries.call_by_account(from: today - 10, to: today, account_ids: [ account.id ])[account.id]
      expect(series[today - 10]).to be_within(0.01).of(25_250)
      expect(series[today]).to eq(0)
    end
  end
end
