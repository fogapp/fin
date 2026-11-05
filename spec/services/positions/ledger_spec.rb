require "rails_helper"

RSpec.describe Positions::Ledger do
  let(:account)  { create(:account) }
  let(:security) { create(:security) }

  def txn!(type, quantity, cost, date)
    create(:investment_transaction, account: account, security: security, transaction_type: type,
           quantity: quantity, cost_usd: cost, trade_date: date)
  end

  it "nets inbound against outbound whatever sign the provider used, clamping cost at zero" do
    txn!(create(:transaction_type, :purchase), 10, 1000, Date.new(2026, 1, 5))
    txn!(create(:transaction_type, :sale), -4, -1500, Date.new(2026, 2, 5))

    totals = described_class.totals(account_id: account.id, security_id: security.id)

    expect(totals.quantity).to eq(6)
    expect(totals.cost).to eq(0)
    expect(totals.first_acquired_on).to eq(Date.new(2026, 1, 5))
  end

  it "nets in current share units, applying share splits but not spin-off adjustments" do
    txn!(create(:transaction_type, :purchase), 10, 1000, Date.new(2026, 1, 5))
    txn!(create(:transaction_type, :sale), -8, -800, Date.new(2026, 6, 23)) # on the ex date: already post-split
    CorporateAction.create!(security: security, kind: "split", ratio: 4, ex_date: Date.new(2026, 6, 23), source: "tiingo")
    CorporateAction.create!(security: security, kind: "split", ratio: 1.061, ex_date: Date.new(2026, 3, 1), source: "tiingo")

    expect(described_class.totals(account_id: account.id, security_id: security.id).quantity).to eq(32) # 40 - 8
  end

  it "is zero for a pair with no position-affecting history" do
    totals = described_class.totals(account_id: account.id, security_id: security.id)

    expect([ totals.quantity, totals.cost, totals.first_acquired_on ]).to eq([ 0, 0, nil ])
  end

  it "totals every pair at once exactly as it totals each alone" do
    purchase = create(:transaction_type, :purchase)
    sale     = create(:transaction_type, :sale)
    split    = create(:security)
    other_account = create(:account)
    txn!(purchase, 10, 1000, Date.new(2026, 1, 5))
    txn!(sale, -4, -300, Date.new(2026, 2, 5))
    create(:investment_transaction, account: account, security: split, transaction_type: purchase,
           quantity: 5, cost_usd: 500, trade_date: Date.new(2026, 1, 5))
    CorporateAction.create!(security: split, kind: "split", ratio: 2, ex_date: Date.new(2026, 3, 1), source: "tiingo")
    create(:investment_transaction, account: other_account, security: security, transaction_type: sale,
           quantity: 3, cost_usd: 90, trade_date: Date.new(2026, 4, 1)) # outbound only

    by_pair = described_class.totals_by_pair(InvestmentTransaction.all)

    pairs = [ [ account.id, security.id ], [ account.id, split.id ], [ other_account.id, security.id ] ]
    expect(by_pair.keys).to match_array(pairs)
    pairs.each do |account_id, security_id|
      expect(by_pair[[ account_id, security_id ]].to_h)
        .to eq(described_class.totals(account_id: account_id, security_id: security_id).to_h)
    end
    expect(by_pair[[ account.id, security.id ]].to_h).to eq(quantity: 6, cost: 700, first_acquired_on: Date.new(2026, 1, 5))
    expect(by_pair[[ account.id, split.id ]].quantity).to eq(10)
    expect(by_pair[[ other_account.id, security.id ]].quantity).to eq(-3)
  end
end
