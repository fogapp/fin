require "rails_helper"

RSpec.describe BumpsHouseholdDataVersion do
  let!(:account) { create(:account) }

  it "bumps immediately for every committed write outside the executor" do
    expect(Households::DataVersion).to receive(:bump!).with(Current.household.id).twice
    create(:cash_transaction, account: account)
    create(:cash_transaction, account: account)
  end

  it "coalesces a bulk write inside the executor to two bumps (first write + final flush)" do
    household = Current.household
    bumps = 0
    allow(Households::DataVersion).to receive(:bump!).with(household.id) { bumps += 1 }

    Rails.application.executor.wrap do
      # The executor clears CurrentAttributes on entry; restore the spec's
      # household so factories scope correctly.
      Current.household = household
      5.times { create(:cash_transaction, account: account, household: household) }
      # First committed write bumps right away so concurrent readers rotate.
      expect(bumps).to eq(1)
    end

    # Executor completion resets Current, which flushes exactly one deferred
    # bump for the suppressed writes.
    expect(bumps).to eq(2)
  end

  it "reaches the household through the named association for models without household_id" do
    household = Current.household
    bumps = 0
    allow(Households::DataVersion).to receive(:bump!).with(household.id) { bumps += 1 }

    Rails.application.executor.wrap do
      Current.household = household
      3.times do |n|
        AccountBalanceSnapshot.create!(account: account, source: "scheduled", balance: n, recorded_at: n.days.ago)
      end
      expect(bumps).to eq(1) # coalesced, not one per snapshot
    end

    expect(bumps).to eq(2)
  end

  it "bumps the household when a tag is added to a transaction" do
    txn = create(:cash_transaction, account: account)
    tag = Tag.create!(name: "Trip")

    expect(Households::DataVersion).to receive(:bump!).with(Current.household.id)
    CashTransactionTag.create!(cash_transaction: txn, tag: tag)
  end
end
