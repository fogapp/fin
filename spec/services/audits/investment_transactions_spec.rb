require "rails_helper"

RSpec.describe Audits::InvestmentTransactions do
  let(:account)   { create(:account) }
  let(:sale_type) { create(:transaction_type, :sale) }

  def trade!(security, date)
    create(:investment_transaction, account: account, security: security, trade_date: date, quantity: 5,
                                    transaction_type: sale_type)
  end

  def open_no_price_keys
    Issue.active.where("key LIKE ?", "security_no_prices:%").pluck(:key)
  end

  it "flags a held or recently traded security with no price from any source" do
    held   = create(:security, :without_ticker, name: "Solano Cnty Ca Cmnty Clg 4%")
    recent = create(:security, ticker: "MSCI")
    trade!(held, Date.current - (3 * 365))
    trade!(recent, Date.current - 100)
    create(:position_snapshot, account: account, security: held, quantity: 50_000, price: 101, market_value: 50_500)

    described_class.new.call

    expect(open_no_price_keys).to contain_exactly("security_no_prices:#{held.id}", "security_no_prices:#{recent.id}")
  end

  it "doesn't flag, and resolves, a security sold outside the valuation window" do
    ancient = create(:security, ticker: "EPAM")
    trade!(ancient, Date.current - (3 * 365))
    Issue.raise_once!(key: "security_no_prices:#{ancient.id}", title: "No price data — EPAM", body: "x",
                      severity: Severity::Warning, source: "system_audit")

    described_class.new.call

    expect(open_no_price_keys).to be_empty
  end

  it "counts custodian closes (candles only, no legacy row) as price history" do
    bond = create(:security, :without_ticker, name: "Pomona Ca Unif Sch Dist 5%")
    trade!(bond, Date.current - 10)
    Candle.create!(security: bond, date: Date.current, close: 101, currency: "USD", source: MarketData::CustodianPrices::SOURCE)

    described_class.new.call

    expect(open_no_price_keys).to be_empty
  end

  it "auto-resolves once prices arrive" do
    sec = create(:security, ticker: "TER")
    trade!(sec, Date.current - 10)
    described_class.new.call
    expect(open_no_price_keys).to eq([ "security_no_prices:#{sec.id}" ])

    create(:candle, security: sec, date: Date.current - 1)
    described_class.new.call

    expect(open_no_price_keys).to be_empty
  end

  it "reads the open issues in one query however many securities lack prices" do
    securities = %w[AAA BBB CCC].map { |t| create(:security, ticker: t) }
    securities.each { |s| trade!(s, Date.current - 100) }
    described_class.new.call
    Issue.find_by!(key: "security_no_prices:#{securities.first.id}").dismiss!

    queries = count_queries { described_class.new.call }

    expect(queries.grep(/SELECT "issues".* FROM "issues"/).size).to eq(1)
    expect(open_no_price_keys).to match_array(securities.map { |s| "security_no_prices:#{s.id}" })
  end
end
