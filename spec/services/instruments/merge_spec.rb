require "rails_helper"

RSpec.describe Instruments::Merge do
  let(:account) { create(:account) }
  let(:keep)    { create(:security, ticker: "VTI", cusip: "922908769", instrument_class: "etf") }
  let(:remove)  { create(:security, ticker: "VTI", cusip: nil, instrument_class: "etf") }

  it "repoints transactions, prices, snapshots, and watches, keeper winning conflicts" do
    tt = create(:transaction_type, :purchase)
    txn = create(:investment_transaction, security: remove, account: account, transaction_type: tt)

    create(:market_price, security: keep, date: Date.new(2026, 1, 2), close: 100)
    create(:market_price, security: remove, date: Date.new(2026, 1, 2), close: 999) # conflict → dropped
    create(:market_price, security: remove, date: Date.new(2026, 1, 3), close: 101) # moves

    create(:position_snapshot, security: keep, account: account, as_of_date: Date.new(2026, 1, 2),
           source_row_hash: "k1", quantity: 10)
    create(:position_snapshot, security: remove, account: account, as_of_date: Date.new(2026, 1, 2),
           source_row_hash: "r1", quantity: 99) # conflict → dropped
    create(:position_snapshot, security: remove, account: account, as_of_date: Date.new(2026, 1, 5),
           source_row_hash: "r2", quantity: 12) # moves

    SecurityWatch.create!(security: keep, household: Current.household)
    SecurityWatch.create!(security: remove, household: Current.household) # duplicate → dropped

    described_class.call(keep: keep, remove: remove)

    expect(Security.exists?(remove.id)).to be(false)
    expect(txn.reload.security_id).to eq(keep.id)
    expect(MarketPrice.where(security_id: keep.id).pluck(:date, :close).to_h)
      .to eq(Date.new(2026, 1, 2) => 100, Date.new(2026, 1, 3) => 101)
    expect(PositionSnapshot.where(security_id: keep.id).pluck(:quantity)).to contain_exactly(10, 12)
    expect(SecurityWatch.where(security_id: keep.id).count).to eq(1)
  end

  it "migrates candles, quotes, corporate actions, data links, and positions instead of cascading them away" do
    Candle.create!(security: keep, granularity: "1d", date: Date.new(2026, 1, 2), close: 100, source: "av")
    Candle.create!(security: remove, granularity: "1d", date: Date.new(2026, 1, 2), close: 999, source: "av") # conflict → dropped
    Candle.create!(security: remove, granularity: "1d", date: Date.new(2026, 1, 3), close: 101, source: "av") # moves

    InstrumentQuote.create!(security: remove, price: 55, currency: "USD",
                            source: "coin_market_cap", as_of: Time.current) # keeper has none → adopted

    CorporateAction.create!(security: keep, kind: "split", ex_date: Date.new(2026, 1, 2), ratio: 2, source: "av")
    CorporateAction.create!(security: remove, kind: "split", ex_date: Date.new(2026, 1, 2), ratio: 4, source: "av") # conflict → dropped
    CorporateAction.create!(security: remove, kind: "dividend", ex_date: Date.new(2026, 1, 5), amount: 1, source: "av") # moves

    InstrumentDataLink.create!(security: keep, provider: "alpha_vantage", capability: "candles")
    InstrumentDataLink.create!(security: remove, provider: "coin_gecko", capability: "candles") # conflict → dropped
    InstrumentDataLink.create!(security: remove, provider: "coin_gecko", capability: "quotes")  # moves

    Position.create!(household: Current.household, account: account, security: keep, quantity: 10)
    Position.create!(household: Current.household, account: account, security: remove, quantity: 99) # conflict → dropped
    other_account = create(:account)
    Position.create!(household: Current.household, account: other_account, security: remove, quantity: 12) # moves

    described_class.call(keep: keep, remove: remove)

    expect(Candle.where(security_id: keep.id).pluck(:date, :close).to_h)
      .to eq(Date.new(2026, 1, 2) => 100, Date.new(2026, 1, 3) => 101)
    expect(InstrumentQuote.where(security_id: keep.id).sole.price).to eq(55)
    expect(CorporateAction.where(security_id: keep.id).pluck(:kind, :ratio, :amount))
      .to contain_exactly([ "split", 2, nil ], [ "dividend", nil, 1 ])
    expect(InstrumentDataLink.where(security_id: keep.id).pluck(:capability, :provider))
      .to contain_exactly(
        [ MarketData::Capability::Candles, MarketData::Provider::AlphaVantage ],
        [ MarketData::Capability::Quotes, MarketData::Provider::CoinGecko ]
      )
    expect(Position.where(security_id: keep.id).pluck(:account_id, :quantity))
      .to contain_exactly([ account.id, 10 ], [ other_account.id, 12 ])
  end

  it "keeps the keeper's live quote when both have one" do
    InstrumentQuote.create!(security: keep, price: 42, currency: "USD",
                            source: "coin_market_cap", as_of: Time.current)
    InstrumentQuote.create!(security: remove, price: 55, currency: "USD",
                            source: "coin_market_cap", as_of: Time.current)

    described_class.call(keep: keep, remove: remove)

    expect(InstrumentQuote.where(security_id: keep.id).sole.price).to eq(42)
    expect(InstrumentQuote.count).to eq(1)
  end

  it "adopts missing metadata from the removed row" do
    keep.update!(name: nil)
    remove.update!(name: "Vanguard Total Market", cusip: nil)

    described_class.call(keep: keep, remove: remove)
    expect(keep.reload.name).to eq("Vanguard Total Market")
  end

  it "adopts the removed row's cusip — which only frees up once it is gone" do
    keep.update!(cusip: nil)
    remove.update!(cusip: "544647HQ6")

    described_class.call(keep: keep, remove: remove)

    expect(keep.reload.cusip).to eq("544647HQ6")
  end

  it "keeps its own cusip rather than the removed row's" do
    keep.update!(cusip: "922908769")
    remove.update!(cusip: "544647HQ6")

    described_class.call(keep: keep, remove: remove)

    expect(keep.reload.cusip).to eq("922908769")
  end

  it "carries a household label over rather than cascading it away" do
    create(:security_label, security: remove, household: Current.household, label: "Emergency fund")

    described_class.call(keep: keep, remove: remove)

    expect(SecurityLabel.where(security_id: keep.id).sole.label).to eq("Emergency fund")
  end

  it "keeps the label already on the keeper when both are labelled" do
    create(:security_label, security: keep,   household: Current.household, label: "Mine")
    create(:security_label, security: remove, household: Current.household, label: "Stale")

    described_class.call(keep: keep, remove: remove)

    expect(SecurityLabel.where(security_id: keep.id).sole.label).to eq("Mine")
    expect(SecurityLabel.count).to eq(1)
  end

  it "refuses self-merge" do
    expect { described_class.call(keep: keep, remove: keep) }.to raise_error(ArgumentError)
  end
end
