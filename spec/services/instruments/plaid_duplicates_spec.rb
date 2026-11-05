require "rails_helper"

RSpec.describe Instruments::PlaidDuplicates do
  let(:account) { create(:account) }

  # The resolver-era row: identified, still syncing.
  def keeper(name:, as_of: Date.current)
    security = create(:security, name: name, ticker: nil, cusip: nil)
    Instruments::Resolver.register!(security, { "plaid_security_id" => "plaid-#{security.id}" })
    snapshot(security, as_of: as_of, market_value: 1_000)
    security
  end

  # The pre-resolver row: no identifiers, frozen at the cutover.
  def orphan(name:, as_of: 1.month.ago.to_date, market_value: 900)
    security = create(:security, name: name, ticker: nil, cusip: nil)
    InstrumentIdentifier.unscoped.where(security_id: security.id).delete_all
    snapshot(security, as_of: as_of, market_value: market_value)
    security
  end

  def snapshot(security, as_of:, market_value:, account: self.account, source: "plaid_holding:acct:#{SecureRandom.uuid}")
    create(:position_snapshot, security: security, account: account, as_of_date: as_of,
                               source_row_hash: source, market_value: market_value)
  end

  it "pairs a frozen identifier-less row with the identified one that replaced it" do
    keep   = keeper(name: "Hps Corporate Lending Fund")
    remove = orphan(name: "Hps Corporate Lending Fund", market_value: 372_006.39)

    result = described_class.new.call

    expect(result.skipped).to be_empty
    pair = result.pairs.sole
    expect(pair.keep.id).to eq(keep.id)
    expect(pair.remove.id).to eq(remove.id)
    expect(pair.account_id).to eq(account.id)
    expect(pair.stale_market_value).to eq(372_006.39)
  end

  it "ignores a name held under a single security" do
    keeper(name: "Hps Corporate Lending Fund")
    expect(described_class.new.call.pairs).to be_empty
  end

  it "ignores the same name in two different accounts" do
    other = create(:account)
    keep  = keeper(name: "Muni Bond 5%")
    snapshot(keep, as_of: Date.current, market_value: 500, account: other)

    expect(described_class.new.call.pairs).to be_empty
  end

  it "ignores rows that are not Plaid observations" do
    keep = keeper(name: "Muni Bond 5%")
    stale = create(:security, name: "Muni Bond 5%", ticker: nil, cusip: nil)
    InstrumentIdentifier.unscoped.where(security_id: stale.id).delete_all
    create(:position_snapshot, security: stale, account: account, as_of_date: 1.month.ago.to_date,
                               source_row_hash: "import:batch-1")

    result = described_class.new.call
    expect(result.pairs).to be_empty
    expect(keep.reload).to be_present
  end

  it "reports rather than merges when neither row is identified" do
    orphan(name: "Muni Bond 5%")
    orphan(name: "Muni Bond 5%", as_of: Date.current)

    result = described_class.new.call
    expect(result.pairs).to be_empty
    expect(result.skipped.sole.reason).to match(/exactly one identified row, got 0/)
  end

  it "reports rather than merges when both rows are identified" do
    keeper(name: "Muni Bond 5%")
    keeper(name: "Muni Bond 5%", as_of: 1.week.ago.to_date)

    result = described_class.new.call
    expect(result.pairs).to be_empty
    expect(result.skipped.sole.reason).to match(/exactly one identified row, got 2/)
  end

  it "reports rather than merges when the identifier-less row is the fresher one" do
    keeper(name: "Muni Bond 5%", as_of: 1.month.ago.to_date)
    orphan(name: "Muni Bond 5%", as_of: Date.current)

    result = described_class.new.call
    expect(result.pairs).to be_empty
    expect(result.skipped.sole.reason).to match(/not stale/)
  end

  it "collapses a duplicate held in several accounts into one merge" do
    other = create(:account)
    keep   = keeper(name: "US Dollar")
    snapshot(keep, as_of: Date.current, market_value: 1_000, account: other)
    remove = orphan(name: "US Dollar", market_value: 858.33)
    snapshot(remove, as_of: 1.month.ago.to_date, market_value: 29_360.56, account: other)

    result = described_class.new
    expect(result.plans.size).to eq(1)
    plan = result.plans.sole
    expect(result.pairs.size).to eq(2)
    expect(plan.keep.id).to eq(keep.id)
    expect(plan.remove.id).to eq(remove.id)
    expect(plan.account_ids).to contain_exactly(account.id, other.id)
    expect(plan.stale_market_value).to eq(858.33 + 29_360.56)
  end

  it "reports rather than merges when one duplicate maps to different keepers" do
    other = create(:account)
    keeper(name: "US Dollar") # replaces the orphan in `account`
    # A different security replaces the same orphan in the second account.
    other_keeper = create(:security, name: "US Dollar", ticker: nil, cusip: nil)
    Instruments::Resolver.register!(other_keeper, { "plaid_security_id" => "plaid-#{other_keeper.id}" })
    snapshot(other_keeper, as_of: Date.current, market_value: 5, account: other)

    orphan_row = orphan(name: "US Dollar")
    snapshot(orphan_row, as_of: 1.month.ago.to_date, market_value: 5, account: other)

    result = described_class.new
    expect(result.plans).to be_empty
    expect(result.skipped).not_to be_empty
  end

  it "merging a found pair leaves one row carrying the full history" do
    keep   = keeper(name: "Hps Corporate Lending Fund")
    remove = orphan(name: "Hps Corporate Lending Fund")
    tt     = create(:transaction_type, :purchase)
    txn    = create(:investment_transaction, security: remove, account: account, transaction_type: tt)
    lot    = create(:investment_lot, security: remove, account: account)

    pair = described_class.new.call.pairs.sole
    Instruments::Merge.call(keep: pair.keep, remove: pair.remove)

    expect(Security.exists?(remove.id)).to be(false)
    expect(txn.reload.security_id).to eq(keep.id)
    expect(lot.reload.security_id).to eq(keep.id)
    expect(PositionSnapshot.where(security_id: keep.id).count).to eq(2)
    expect(described_class.new.call.pairs).to be_empty
  end
end
