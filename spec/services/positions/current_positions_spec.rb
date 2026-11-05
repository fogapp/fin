require "rails_helper"

RSpec.describe Positions::CurrentPositions do
  let(:broker)   { create(:broker) }
  let(:account)  { create(:account, broker: broker) }
  let(:plaid_account) { create(:account, broker: broker, name: "Plaid Acct", account_number: "P1") }

  def imported_snap(security, as_of:, value:, acct: account)
    create(:position_snapshot, account: acct, security: security, as_of_date: as_of,
           market_value: value, quantity: 1,
           source_row_hash: "csv-#{security.id}-#{as_of}")
  end

  def plaid_snap(security, value:, acct: plaid_account, as_of: Date.current)
    create(:position_snapshot, account: acct, security: security, as_of_date: as_of,
           market_value: value, quantity: 1,
           source_row_hash: "plaid_holding:#{acct.id}:#{security.id}")
  end

  def computed_snap(security, value:, as_of: Date.current, acct: account)
    create(:position_snapshot, account: acct, security: security, as_of_date: as_of,
           market_value: value, quantity: 1,
           source_row_hash: "computed:#{security.id}:#{acct.id}")
  end

  it "keeps CSV-imported positions when Plaid rows carry a newer date" do
    # The original bug: plaid_holding rows counted as an imported batch dated
    # today, evicting every CSV position on every sync.
    csv_sec   = create(:security, ticker: "VTI")
    plaid_sec = create(:security, ticker: "AAPL")
    imported_snap(csv_sec, as_of: 3.weeks.ago.to_date, value: 500_000)
    plaid_snap(plaid_sec, value: 10_000)

    current = described_class.new
    values = current.relation.joins(:security).pluck("securities.ticker", :market_value).to_h

    expect(values.keys).to contain_exactly("VTI", "AAPL")
    expect(values["VTI"].to_f).to eq(500_000.0)
    expect(current.as_of_date).to eq(3.weeks.ago.to_date)
  end

  it "does not double count the same account+security described by both CSV and Plaid" do
    sec = create(:security, ticker: "VTI")
    imported_snap(sec, as_of: 1.week.ago.to_date, value: 100_000)
    plaid_snap(sec, value: 101_000, acct: account) # same account — imported wins

    total = described_class.new.relation.sum(:market_value).to_f
    expect(total).to eq(100_000.0)
  end

  it "counts the same security held in two different accounts twice" do
    sec = create(:security, ticker: "VTI")
    imported_snap(sec, as_of: 1.week.ago.to_date, value: 100_000)
    plaid_snap(sec, value: 50_000) # plaid_account — a genuinely separate position

    total = described_class.new.relation.sum(:market_value).to_f
    expect(total).to eq(150_000.0)
  end

  it "shows only the latest plaid observation per account+security" do
    sec = create(:security, ticker: "VTI")
    [ 3.weeks.ago, 2.weeks.ago, 1.week.ago ].each_with_index do |date, i|
      create(:position_snapshot, account: plaid_account, security: sec,
             as_of_date: date.to_date, quantity: 10 + i, market_value: 1000 + i,
             source_row_hash: "plaid_holding:#{plaid_account.id}:#{sec.id}:#{date.to_date}")
    end

    current = described_class.new
    rows = current.relation.to_a
    expect(rows.size).to eq(1)
    expect(rows.sole.quantity).to eq(12) # the 1-week-ago observation
  end

  it "shows a computed-only portfolio even when the rows are stale" do
    manual = create(:security, ticker: "MANL")
    computed_snap(manual, value: 5_000, as_of: 3.weeks.ago.to_date)

    current = described_class.new
    expect(current.relation.sum(:market_value).to_f).to eq(5_000.0)
  end

  it "appends computed positions for uncovered securities without advancing as_of" do
    csv_sec  = create(:security, ticker: "VTI")
    manual   = create(:security, ticker: "MANL")
    imported_snap(csv_sec, as_of: 1.week.ago.to_date, value: 100_000)
    computed_snap(manual, value: 5_000)

    current = described_class.new
    expect(current.as_of_date).to eq(1.week.ago.to_date)
    expect(current.relation.count).to eq(2)
  end

  it "works for Plaid-only portfolios" do
    sec = create(:security, ticker: "AAPL")
    plaid_snap(sec, value: 42_000)

    current = described_class.new
    expect(current.as_of_date).to eq(Date.current)
    expect(current.relation.sum(:market_value).to_f).to eq(42_000.0)
  end

  describe "stale Plaid observations" do
    # The July 2026 resolver cutover: Plaid kept syncing the account, but into
    # a differently-keyed security. The abandoned row froze and kept being
    # counted alongside its replacement.
    it "drops a row the account's later syncs stopped refreshing" do
      live      = create(:security, ticker: "AAPL")
      abandoned = create(:security, ticker: nil, name: "Apple Inc.")
      plaid_snap(live, value: 42_000)
      plaid_snap(abandoned, value: 41_000, as_of: 1.month.ago.to_date)

      current = described_class.new
      expect(current.relation.pluck(:security_id)).to eq([ live.id ])
      expect(current.relation.sum(:market_value).to_f).to eq(42_000.0)
    end

    it "keeps a row still inside the grace window" do
      sec   = create(:security, ticker: "AAPL")
      other = create(:security, ticker: "MSFT")
      plaid_snap(sec, value: 42_000)
      plaid_snap(other, value: 1_000, as_of: (Positions::CurrentPositions::STALE_AFTER_DAYS - 1).days.ago.to_date)

      expect(described_class.new.relation.sum(:market_value).to_f).to eq(43_000.0)
    end

    it "keeps the whole portfolio of an account that stopped syncing altogether" do
      sec   = create(:security, ticker: "AAPL")
      other = create(:security, ticker: "MSFT")
      plaid_snap(sec,   value: 42_000, as_of: 3.months.ago.to_date)
      plaid_snap(other, value: 1_000,  as_of: 3.months.ago.to_date)

      expect(described_class.new.relation.sum(:market_value).to_f).to eq(43_000.0)
    end

    it "measures staleness per account, not across the portfolio" do
      fresh_sec = create(:security, ticker: "AAPL")
      quiet_sec = create(:security, ticker: "MSFT")
      quiet_account = create(:account, broker: broker, name: "Quiet", account_number: "P2")
      plaid_snap(fresh_sec, value: 42_000)
      plaid_snap(quiet_sec, value: 1_000, acct: quiet_account, as_of: 3.months.ago.to_date)

      expect(described_class.new.relation.sum(:market_value).to_f).to eq(43_000.0)
    end
  end
end
