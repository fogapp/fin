require "rails_helper"

RSpec.describe Positions::ResolvedCostBasis do
  let(:security) { create(:security) }
  let(:account)  { create(:account) }
  let(:purchase) { create(:transaction_type, :purchase) }

  def lots(quantity:, cost_basis:)
    create(:investment_lot, security: security, account: account, quantity: quantity, cost_basis: cost_basis)
  end

  def bought(quantity:, amount:)
    create(:investment_transaction, security: security, account: account, transaction_type: purchase,
           quantity: quantity, amount_usd: -amount)
  end

  def resolve(quantity:, snapshot:)
    described_class.new([ security.id ]).resolve(security.id, quantity: quantity, snapshot_cost_basis: snapshot)
  end

  source = Positions::ResolvedCostBasis::Source

  [
    # [description, lot qty, lot cost, ledger qty/amount, snapshot, expected basis, expected source]
    [ "lots covering >= 95% win over the snapshot", 96.0, 900.0, nil, 1_000.0, 900.0, source::Lots ],
    [ "lots covering < 95% fall back to the snapshot", 10.0, 50.0, nil, 1_000.0, 1_000.0, source::Snapshot ],
    [ "no lots and a zero snapshot use the ledger", nil, nil, [ 100.0, 700.0 ], 0.0, 700.0, source::Computed ],
    [ "no lots with a snapshot basis keep it", nil, nil, [ 100.0, 700.0 ], 1_000.0, 1_000.0, source::Snapshot ],
    [ "nothing to go on reports none", nil, nil, nil, 0.0, 0.0, source::None ]
  ].each do |desc, lot_qty, lot_cost, ledger, snapshot, expected_basis, expected_source|
    it desc do
      lots(quantity: lot_qty, cost_basis: lot_cost) if lot_qty
      bought(quantity: ledger[0], amount: ledger[1]) if ledger

      result = resolve(quantity: 100.0, snapshot: snapshot)
      expect(result.cost_basis).to be_within(0.01).of(expected_basis)
      expect(result.source).to eq(expected_source)
    end
  end

  it "reports lot coverage against the held quantity" do
    lots(quantity: 25.0, cost_basis: 100.0)
    expect(described_class.new([ security.id ]).lot_coverage(security.id, quantity: 100.0)).to eq(0.25)
  end
end
