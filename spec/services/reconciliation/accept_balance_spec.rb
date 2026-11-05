require "rails_helper"

RSpec.describe Reconciliation::AcceptBalance do
  let(:account)  { create(:account) }
  let(:security) { create(:security, ticker: "AAPL") }
  let(:purchase_type) { create(:transaction_type, :purchase) }

  def observe!(qty, as_of: Date.current)
    create(:position_snapshot, account: account, security: security, as_of_date: as_of,
           quantity: qty, source_row_hash: "plaid_holding:#{account.id}:#{security.id}:#{as_of}")
  end

  it "writes a positive adjustment when the custodian reports more than the ledger" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 40, cost_usd: 4000)
    observe!(100)
    InstrumentQuote.create!(security: security, price: 50, currency: "USD",
                            source: "coin_market_cap", as_of: Time.current)

    result = described_class.call(account: account, security: security)

    expect(result.status).to eq(:adjusted)
    expect(result.delta).to eq(60)
    adj = InvestmentTransaction.joins(:transaction_type)
                               .where(transaction_types: { code: "ADJ-IN" }).sole
    expect(adj.quantity).to eq(60)
    expect(adj.cost_usd).to eq(3000) # 60 × $50
    expect(Position.sole.quantity).to eq(100)
  end

  it "writes a negative adjustment when the ledger over-counts" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 120, cost_usd: 12_000)
    observe!(100)

    result = described_class.call(account: account, security: security)

    expect(result.status).to eq(:adjusted)
    adj = InvestmentTransaction.joins(:transaction_type)
                               .where(transaction_types: { code: "ADJ-OUT" }).sole
    expect(adj.quantity).to eq(-20)
    expect(Position.sole.quantity).to eq(100)
  end

  it "resolves the drift issue and is idempotent" do
    observe!(50)
    Issue.raise_once!(key: "reconciliation:#{account.id}:#{security.id}",
                      title: "drift", source: "reconciliation")

    described_class.call(account: account, security: security)
    expect(Issue.active.where("key LIKE 'reconciliation:%'")).to be_empty

    result = described_class.call(account: account, security: security)
    expect(result.status).to eq(:in_sync)
    expect(InvestmentTransaction.count).to eq(1)
  end

  it "does not trigger workflows from adjustment transactions" do
    create(:workflow, trigger_type: "investment_transaction.created")
    Workflows::Events.reset_cache
    observe!(10)

    expect {
      described_class.call(account: account, security: security)
    }.not_to have_enqueued_job(Workflows::DispatchJob)
  end

  it "no-ops without a custodian observation" do
    expect(described_class.call(account: account, security: security).status).to eq(:no_observation)
  end

  describe Reconciliation::AcceptAllJob do
    it "accepts every open drift finding and records a summary" do
      other_sec = create(:security, ticker: "MSFT")
      observe!(10)
      create(:position_snapshot, account: account, security: other_sec, as_of_date: Date.current,
             quantity: 5, source_row_hash: "plaid_holding:#{account.id}:#{other_sec.id}:x")
      Positions::Rebuild.all(household: Current.household)
      Reconciliation::Engine.run(Current.household)
      expect(Issue.active.where("key LIKE 'reconciliation:%'").count).to eq(2)

      described_class.perform_now(Current.household.id.to_s)

      expect(Issue.active.where("key LIKE 'reconciliation:%'")).to be_empty
      expect(Position.count).to eq(2)
      summary = ActivityEntry.where(event: "balances_accepted").sole
      expect(summary.payload["adjusted"]).to eq(2)
      # Accepted balances survive the next reconciliation run
      expect(Reconciliation::Engine.run(Current.household)).to be_empty
    end
  end
end
