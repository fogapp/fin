require "rails_helper"

RSpec.describe Reconciliation::Engine do
  let(:household) { Current.household }
  let(:account)   { create(:account) }
  let(:security)  { create(:security, ticker: "AAPL") }
  let(:purchase_type) { create(:transaction_type, :purchase) }

  def observe!(qty, sec: security, acct: account, as_of: Date.current)
    create(:position_snapshot, account: acct, security: sec, as_of_date: as_of,
           quantity: qty, source_row_hash: "csv-#{sec.id}-#{as_of}-#{qty}")
  end

  def ledger!(qty, sec: security, acct: account)
    create(:investment_transaction, account: acct, security: sec,
           transaction_type: purchase_type, quantity: qty, cost_usd: qty * 100)
    Positions::Rebuild.call(account: acct, security: sec)
  end

  it "finds nothing when ledger and custodian agree" do
    ledger!(100)
    observe!(100)

    findings = described_class.run(household)
    expect(findings).to be_empty
    expect(Issue.active.where("key LIKE 'reconciliation:%'")).to be_empty
  end

  it "raises a drift issue, workflow event, and activity entry on quantity mismatch" do
    create(:workflow, name: "Drift alert", trigger_type: "reconciliation.drift_detected")
    Workflows::Events.reset_cache
    ledger!(82)
    observe!(100)

    findings = nil
    expect {
      findings = described_class.run(household)
    }.to have_enqueued_job(Workflows::DispatchJob)

    finding = findings.sole
    expect(finding.kind).to eq(Reconciliation::FindingKind::QuantityDrift)
    expect(finding.ledger_qty).to eq(82)
    expect(finding.observed_qty).to eq(100)

    issue = Issue.active.find_by!(key: "reconciliation:#{account.id}:#{security.id}")
    expect(issue.title).to match(/AAPL/)
    expect(ActivityEntry.where(source: "reconciliation").sole.severity).to eq(Severity::Warning)
  end

  it "flags custodian-only holdings as missing_from_ledger" do
    observe!(50)

    findings = described_class.run(household)
    expect(findings.sole.kind).to eq(Reconciliation::FindingKind::MissingFromLedger)
  end

  it "flags ledger-only holdings in observed accounts as missing_from_custodian" do
    other_sec = create(:security, ticker: "MSFT")
    observe!(10) # account is custodian-observed for AAPL
    ledger!(100, sec: other_sec)
    observe!(100, sec: other_sec) # MSFT agrees

    ledger!(10) # AAPL ledger agrees too... adjust: make AAPL agree, add ledger-only pair
    third = create(:security, ticker: "ORCL")
    ledger!(7, sec: third)

    findings = described_class.run(household)
    expect(findings.map { |f| [ f.security.ticker, f.kind ] })
      .to include([ "ORCL", Reconciliation::FindingKind::MissingFromCustodian ])
  end

  it "auto-resolves the issue when drift clears" do
    ledger!(82)
    observe!(100)
    described_class.run(household)
    expect(Issue.active.where("key LIKE 'reconciliation:%'").count).to eq(1)

    ledger!(18) # ledger catches up to 100
    described_class.run(household)
    expect(Issue.active.where("key LIKE 'reconciliation:%'")).to be_empty
  end

  it "tolerates sub-threshold rounding differences" do
    ledger!(100)
    observe!(100.00005)

    expect(described_class.run(household)).to be_empty
  end

  it "ignores accounts without custodian observations (manual-only)" do
    ledger!(42) # no snapshots for this account at all... except rebuild doesn't create snapshots
    PositionSnapshot.where(account_id: account.id).delete_all

    expect(described_class.run(household)).to be_empty
  end

  it "raises and resolves drift issues in a fixed number of issue reads" do
    drifting = %w[AAA BBB CCC].map { |t| create(:security, ticker: t) }
    drifting.each { |sec| observe!(10, sec: sec) }
    cleared = create(:security, ticker: "DDD")
    Issue.raise_once!(key: "reconciliation:#{account.id}:#{cleared.id}", title: "old drift")

    queries = count_queries { described_class.run(household) }

    expect(queries.grep(/SELECT "issues".* FROM "issues"/).size).to eq(1)
    expect(Issue.active.where("key LIKE 'reconciliation:%'").pluck(:key))
      .to match_array(drifting.map { |sec| "reconciliation:#{account.id}:#{sec.id}" })
  end
end
