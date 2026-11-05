require "rails_helper"

RSpec.describe HouseholdScoped do
  let!(:household_a) { create(:household, name: "A") }
  let!(:household_b) { create(:household, name: "B") }

  let!(:broker_a) { Current.set(household: household_a) { create(:broker, name: "Bank A") } }
  let!(:broker_b) { Current.set(household: household_b) { create(:broker, name: "Bank B") } }

  describe "default_scope" do
    it "filters by Current.household when set" do
      Current.household = household_a
      expect(Broker.pluck(:id)).to contain_exactly(broker_a.id)

      Current.household = household_b
      expect(Broker.pluck(:id)).to contain_exactly(broker_b.id)
    end

    it "returns all rows when Current.household is unset" do
      Current.reset
      expect(Broker.pluck(:id)).to contain_exactly(broker_a.id, broker_b.id)
    end
  end

  describe "assign_household_from_current" do
    it "auto-fills household_id from Current.household on create" do
      Current.household = household_a
      broker = Broker.create!(name: "Auto")
      expect(broker.household_id).to eq(household_a.id)
    end

    it "does not override an explicitly set household_id" do
      Current.household = household_a
      broker = Broker.new(name: "Explicit", household: household_b)
      broker.save!
      expect(broker.reload.household_id).to eq(household_b.id)
    end
  end

  describe "cross-household isolation" do
    it "prevents a query from seeing the other household's rows" do
      Current.household = household_a
      expect(Broker.find_by(id: broker_b.id)).to be_nil
    end

    it "raises RecordNotFound when finding another household's row by id" do
      Current.household = household_a
      expect { Broker.find(broker_b.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "references to other household-scoped rows" do
    let!(:account_a) { Current.set(household: household_a) { create(:account, broker: broker_a) } }
    let!(:account_b) { Current.set(household: household_b) { create(:account, broker: broker_b) } }

    before { Current.household = household_a }

    it "rejects a foreign key naming another household's row, on create and on update" do
      txn = CashTransaction.new(source: "bank", transaction_date: Date.current, amount: -1, source_row_hash: "hs-1",
                                 account_id: account_b.id)
      expect(txn).not_to be_valid
      expect(txn.errors[:account]).to include("must belong to this household")

      txn.account_id = account_a.id
      txn.save!
      txn.account_id = account_b.id
      expect(txn).not_to be_valid
    end

    it "checks even outside a request, against the record's own household" do
      Current.reset
      account = Account.find(account_a.id)
      account.broker_id = broker_b.id
      expect(account).not_to be_valid
      expect(account.errors[:broker]).to include("must belong to this household")
    end

    it "accepts the household's own rows and a cleared key" do
      other_broker = create(:broker, name: "Bank A2")
      expect(account_a.update(broker_id: other_broker.id)).to be(true)

      txn = CashTransaction.create!(source: "bank", transaction_date: Date.current, amount: -1, source_row_hash: "hs-2",
                                   account_id: account_a.id)
      expect(txn.update(account_id: nil)).to be(true)
    end

    it "leaves unchanged keys alone (a row saved before the check stays editable)" do
      txn = CashTransaction.create!(source: "bank", transaction_date: Date.current, amount: -1, source_row_hash: "hs-3")
      CashTransaction.unscoped.where(id: txn.id).update_all(account_id: account_b.id)
      expect(CashTransaction.find(txn.id).update(memo: "edited")).to be(true)
    end
  end
end
