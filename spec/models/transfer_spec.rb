require "rails_helper"

RSpec.describe Transfer, type: :model do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:external)  { create(:account, kind: "external", broker: nil, account_number: nil) }
  let(:from_txn)  { create(:cash_transaction, :bank, account: account_a, amount: -500.00) }
  let(:to_txn)    { create(:cash_transaction, :bank, account: account_b, amount:  500.00) }

  def pair_transfer(attrs = {})
    Transfer.new({ from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                   to_transaction_id:   to_txn.id,   to_transaction_type:   "CashTransaction",
                   amount: 500.00 }.merge(attrs))
  end

  def one_sided_transfer(attrs = {})
    Transfer.new({ from_transaction_id: from_txn.id, from_transaction_type: "CashTransaction",
                   counterparty_account_id: external.id, amount: 500.00 }.merge(attrs))
  end

  describe "side/counterparty validations" do
    it "rejects a transfer with no transaction sides" do
      t = Transfer.new(amount: 100.00)
      expect(t).not_to be_valid
      expect(t.errors[:base]).to include("Must have at least one transaction side")
    end

    it "accepts a pair transfer without a counterparty" do
      expect(pair_transfer).to be_valid
    end

    it "rejects a counterparty when both sides are present" do
      t = pair_transfer(counterparty_account_id: external.id)
      expect(t).not_to be_valid
      expect(t.errors[:counterparty_account]).to include("must be blank when both transaction sides are present")
    end

    it "requires a counterparty when only one side is present" do
      t = pair_transfer(to_transaction_id: nil, to_transaction_type: nil)
      expect(t).not_to be_valid
      expect(t.errors[:counterparty_account]).to include("is required for a one-sided transfer")
    end

    it "accepts a one-sided transfer with a counterparty (from side)" do
      expect(one_sided_transfer).to be_valid
    end

    it "accepts a one-sided transfer with a counterparty (to side)" do
      t = Transfer.new(to_transaction_id: to_txn.id, to_transaction_type: "CashTransaction",
                       counterparty_account_id: account_a.id, amount: 500.00)
      expect(t).to be_valid
    end

    it "accepts a standard (tracked) account as counterparty" do
      expect(one_sided_transfer(counterparty_account_id: account_b.id)).to be_valid
    end

    it "rejects a counterparty from another household" do
      other_household = Household.create!(name: "Other Household")
      other_account = Current.set(household: other_household) { create(:account) }

      t = one_sided_transfer(counterparty_account_id: other_account.id)
      expect(t).not_to be_valid
      expect(t.errors[:counterparty_account]).to include("must belong to the same household")
    end

    it "rejects a nonexistent counterparty account" do
      t = one_sided_transfer(counterparty_account_id: SecureRandom.uuid)
      expect(t).not_to be_valid
      expect(t.errors[:counterparty_account]).to include("must belong to the same household")
    end

    it "rejects a counterparty equal to the transaction's own account" do
      t = one_sided_transfer(counterparty_account_id: account_a.id)
      expect(t).not_to be_valid
      expect(t.errors[:counterparty_account]).to include("must be a different account than the transaction's own")
    end
  end

  describe "one-sided lifecycle" do
    it "confirm! syncs transfer_id onto the single present side" do
      t = one_sided_transfer
      t.save!
      t.confirm!

      expect(t.confirmed_at).to be_present
      expect(from_txn.reload.transfer_id).to eq(t.id)
    end

    it "destroy unlinks the single present side" do
      t = one_sided_transfer
      t.save!
      t.confirm!
      t.destroy!

      expect(from_txn.reload.transfer_id).to be_nil
    end

    it "nullifies counterparty_account_id when the account is deleted" do
      t = one_sided_transfer(counterparty_account_id: account_b.id)
      t.save!

      account_b.destroy!
      expect(t.reload.counterparty_account_id).to be_nil
    end
  end

  describe "leg destruction dissolves the transfer" do
    it "destroys the transfer and clears the survivor's transfer_id when a cash leg is destroyed" do
      t = pair_transfer
      t.save!
      t.confirm!
      expect(to_txn.reload.transfer_id).to eq(t.id)

      # A Plaid `removed` event destroys one leg — the survivor must not stay
      # excluded from spend/income by a transfer whose other side is gone.
      from_txn.destroy!

      expect(Transfer.exists?(t.id)).to be false
      expect(to_txn.reload.transfer_id).to be_nil
    end

    it "dissolves unconfirmed candidate transfers referencing the destroyed leg too" do
      t = pair_transfer
      t.save!

      from_txn.destroy!
      expect(Transfer.exists?(t.id)).to be false
    end

    it "dissolves transfers referencing a destroyed investment transaction leg" do
      inv = create(:investment_transaction, account: account_a)
      t = Transfer.create!(from_transaction_id: inv.id, from_transaction_type: "InvestmentTransaction",
                           counterparty_account_id: external.id, amount: 100.00)
      t.confirm!
      expect(inv.reload.transfer_id).to eq(t.id)

      inv.destroy!
      expect(Transfer.exists?(t.id)).to be false
    end
  end

  describe "#confirm!" do
    it "rolls back the confirmation when syncing transfer ids fails" do
      t = pair_transfer
      t.save!
      allow(t).to receive(:sync_transfer_ids).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { t.confirm!(source: Transfer::ConfirmationSource::Auto) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(t.reload.confirmed_at).to be_nil
      expect(from_txn.reload.transfer_id).to be_nil
    end
  end
end
