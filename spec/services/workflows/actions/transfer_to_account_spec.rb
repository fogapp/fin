require "rails_helper"

RSpec.describe Workflows::Actions::TransferToAccount do
  let(:checking) { create(:account) }
  let(:target)   { create(:account) }
  let(:txn)      { create(:cash_transaction, :bank, account: checking, amount: -500.00) }

  def action(account_id = target.id)
    described_class.new(account_id: account_id)
  end

  context "when exactly one counterpart exists in the target account" do
    let!(:counterpart) { create(:cash_transaction, :bank, account: target, amount: 500.00) }

    it "creates a confirmed pair transfer with the negative side as from" do
      result = action.execute(txn)

      expect(result[:status]).to eq(:applied)
      expect(result[:counterpart_id]).to eq(counterpart.id)

      transfer = Transfer.find(result[:transfer_id])
      expect(transfer.confirmed_at).to be_present
      expect(transfer.from_transaction_id).to eq(txn.id)
      expect(transfer.to_transaction_id).to eq(counterpart.id)
      expect(transfer.counterparty_account_id).to be_nil
      expect(txn.reload.transfer_id).to eq(transfer.id)
      expect(counterpart.reload.transfer_id).to eq(transfer.id)
    end

    it "does not persist anything in dry_run mode" do
      expect {
        result = action.execute(txn, dry_run: true)
        expect(result[:status]).to eq(:applied)
        expect(result[:dry_run]).to be(true)
        expect(result[:counterpart_id]).to eq(counterpart.id)
      }.not_to change(Transfer, :count)
      expect(txn.reload.transfer_id).to be_nil
    end
  end

  context "when no counterpart exists in the target account" do
    it "creates a confirmed one-sided transfer with the counterparty account" do
      result = action.execute(txn)

      expect(result[:status]).to eq(:applied)
      expect(result[:counterparty_account_id]).to eq(target.id)

      transfer = Transfer.find(result[:transfer_id])
      expect(transfer.confirmed_at).to be_present
      expect(transfer.from_transaction_id).to eq(txn.id)
      expect(transfer.to_transaction_id).to be_nil
      expect(transfer.counterparty_account_id).to eq(target.id)
      expect(txn.reload.transfer_id).to eq(transfer.id)
    end

    it "puts a positive transaction on the to side" do
      deposit = create(:cash_transaction, :bank, account: checking, amount: 500.00)
      result = action.execute(deposit)

      transfer = Transfer.find(result[:transfer_id])
      expect(transfer.to_transaction_id).to eq(deposit.id)
      expect(transfer.from_transaction_id).to be_nil
    end

    it "does not persist anything in dry_run mode" do
      expect {
        result = action.execute(txn, dry_run: true)
        expect(result[:status]).to eq(:applied)
        expect(result[:dry_run]).to be(true)
      }.not_to change(Transfer, :count)
    end

    it "works with an external counterparty account" do
      external = create(:account, kind: "external", broker: nil, account_number: nil, name: "Schwab")
      result = action(external.id).execute(txn)

      expect(result[:status]).to eq(:applied)
      expect(Transfer.find(result[:transfer_id]).counterparty_account_id).to eq(external.id)
    end
  end

  context "when multiple counterparts exist in the target account" do
    before do
      create(:cash_transaction, :bank, account: target, amount: 500.00)
      create(:cash_transaction, :bank, account: target, amount: 500.00,
             transaction_date: Date.current - 1)
    end

    it "falls back to a one-sided transfer instead of guessing" do
      result = action.execute(txn)

      expect(result[:status]).to eq(:applied)
      transfer = Transfer.find(result[:transfer_id])
      expect(transfer.counterparty_account_id).to eq(target.id)
      expect(transfer.to_transaction_id).to be_nil
    end
  end

  it "skips when the transaction is already linked to a transfer" do
    existing = Transfer.create!(from_transaction_id: txn.id, from_transaction_type: "CashTransaction",
                                counterparty_account_id: target.id, amount: 500.00)
    existing.confirm!

    result = action.execute(txn.reload)
    expect(result[:status]).to eq(:skipped)
    expect(result[:reason]).to match(/already linked/)
  end

  it "errors when the account does not exist" do
    missing = SecureRandom.uuid
    result = action(missing).execute(txn)
    expect(result[:status]).to eq(:error)
    expect(result[:error]).to include(missing)
  end

  it "errors when the account belongs to another household" do
    other_household = Household.create!(name: "Other Household")
    other_account = Current.set(household: other_household) { create(:account) }

    result = action(other_account.id).execute(txn)
    expect(result[:status]).to eq(:error)
  end

  it "skips when the transaction is already in the target account" do
    result = action(checking.id).execute(txn)
    expect(result[:status]).to eq(:skipped)
  end

  it "ignores counterparts already linked to another transfer" do
    linked = create(:cash_transaction, :bank, account: target, amount: 500.00)
    other  = create(:cash_transaction, :bank, account: checking, amount: -500.00,
                    transaction_date: Date.current - 1)
    Transfer.create!(from_transaction_id: other.id, from_transaction_type: "CashTransaction",
                     to_transaction_id: linked.id, to_transaction_type: "CashTransaction",
                     amount: 500.00).confirm!

    result = action.execute(txn)
    transfer = Transfer.find(result[:transfer_id])
    expect(transfer.counterparty_account_id).to eq(target.id)
    expect(transfer.to_transaction_id).to be_nil
  end
end
