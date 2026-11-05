require "rails_helper"

RSpec.describe Transfers::Dismiss do
  let(:from_txn) { create(:cash_transaction, :bank, account: create(:account), amount: -500.00) }
  let(:to_txn)   { create(:cash_transaction, :bank, account: create(:account), amount:  500.00) }
  let(:transfer) do
    Transfer.create!(from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                     to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                     amount: 500.00)
  end

  it "records the pair and drops the candidate" do
    described_class.call(transfer)

    expect(Transfer.exists?(transfer.id)).to be(false)
    expect(TransferDismissal.for_pair(from_txn.id, to_txn.id).count).to eq(1)
  end

  it "does not record a second dismissal for an already-dismissed pair" do
    TransferDismissal.record_for!(transfer)

    expect { described_class.call(transfer) }.not_to change(TransferDismissal, :count)
  end

  it "refuses a confirmed transfer" do
    transfer.confirm!

    expect { described_class.call(transfer) }.to raise_error(described_class::ConfirmedTransfer)
    expect(Transfer.exists?(transfer.id)).to be(true)
  end

  it "keeps no dismissal when the destroy fails" do
    allow(transfer).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)

    expect { described_class.call(transfer) }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(TransferDismissal.for_pair(from_txn.id, to_txn.id)).to be_empty
  end
end
