require "rails_helper"

RSpec.describe Transfers::ManualLink do
  let(:from_txn) { create(:cash_transaction, :bank, account: create(:account), amount: -500.00) }
  let(:to_txn)   { create(:cash_transaction, :bank, account: create(:account), amount:  500.00) }
  let(:attrs) do
    { from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
      to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
      amount: 500.00 }
  end

  it "clears a past dismissal of the pair and back-points both legs" do
    TransferDismissal.create!(from_transaction_type: "CashTransaction", from_transaction_id: from_txn.id,
                              to_transaction_type: "CashTransaction", to_transaction_id: to_txn.id)

    transfer = described_class.call(attrs, auto_confirm: false)

    expect(TransferDismissal.for_pair(from_txn.id, to_txn.id)).to be_empty
    expect(from_txn.reload.transfer_id).to eq(transfer.id)
    expect(transfer.confirmed_at).to be_nil
  end

  it "leaves nothing half-written when confirming fails" do
    TransferDismissal.create!(from_transaction_type: "CashTransaction", from_transaction_id: from_txn.id,
                              to_transaction_type: "CashTransaction", to_transaction_id: to_txn.id)
    allow_any_instance_of(Transfer).to receive(:confirm!).and_raise(ActiveRecord::RecordInvalid)

    expect { described_class.call(attrs, auto_confirm: true) }.to raise_error(ActiveRecord::RecordInvalid)

    expect(Transfer.count).to eq(0)
    expect(TransferDismissal.for_pair(from_txn.id, to_txn.id)).to be_present
    expect(from_txn.reload.transfer_id).to be_nil
  end
end
