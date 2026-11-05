require "rails_helper"

RSpec.describe SnapshotAccountBalancesJob, type: :job do
  it "snapshots every account that has a balance" do
    with_balance    = create(:account, balance: 100.0, balance_currency: "USD")
    also_balance    = create(:account, balance: 250.0, balance_currency: "USD")
    without_balance = create(:account, balance: nil)

    expect { described_class.perform_now }
      .to change(AccountBalanceSnapshot, :count).by(2)

    expect(AccountBalanceSnapshot.where(account_id: with_balance.id).count).to eq(1)
    expect(AccountBalanceSnapshot.where(account_id: also_balance.id).count).to eq(1)
    expect(AccountBalanceSnapshot.where(account_id: without_balance.id).count).to eq(0)
  end

  it "logs and continues when one account raises" do
    a = create(:account, balance: 100.0)
    b = create(:account, balance: 200.0)
    call_count = 0
    allow(AccountBalanceSnapshot).to receive(:record) do |account, **|
      call_count += 1
      raise "boom" if account.id == a.id
      AccountBalanceSnapshot.create!(account: account, balance: account.balance,
                                     balance_currency: "USD", source: "scheduled",
                                     recorded_at: Time.current)
    end

    expect(Rails.logger).to receive(:error).with(/account=#{a.id} failed: boom/)

    described_class.perform_now
    expect(call_count).to eq(2)
    expect(AccountBalanceSnapshot.where(account_id: b.id).count).to eq(1)
  end
end
