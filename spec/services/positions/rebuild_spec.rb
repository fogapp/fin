require "rails_helper"

RSpec.describe Positions::Rebuild do
  let(:account)  { create(:account) }
  let(:security) { create(:security) }
  let(:purchase_type) { create(:transaction_type, :purchase) }
  let(:sale_type)     { create(:transaction_type, :sale) }

  it "materializes the net ledger position idempotently" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 10, cost_usd: 1000)
    create(:investment_transaction, account: account, security: security,
           transaction_type: sale_type, quantity: -4, cost_usd: 400)

    2.times { described_class.call(account: account, security: security) }

    position = Position.sole
    expect(position.quantity).to eq(6)
    expect(position.cost_basis).to eq(600)
    expect(position.household_id).to eq(account.household_id)
  end

  it "removes the position when the ledger nets to zero" do
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 5, cost_usd: 500)
    described_class.call(account: account, security: security)
    expect(Position.count).to eq(1)

    create(:investment_transaction, account: account, security: security,
           transaction_type: sale_type, quantity: -5, cost_usd: 500)
    described_class.call(account: account, security: security)
    expect(Position.count).to eq(0)
  end

  it "is enqueued automatically when position-relevant transactions land" do
    expect {
      create(:investment_transaction, account: account, security: security,
             transaction_type: purchase_type, quantity: 5, cost_usd: 500)
    }.to have_enqueued_job(Positions::RebuildJob).with(account.id, security.id)
  end

  it "does not enqueue for non-position categories" do
    dividend_type = create(:transaction_type, :dividend)
    expect {
      create(:investment_transaction, account: account, security: security,
             transaction_type: dividend_type, quantity: 0, amount_usd: 12)
    }.not_to have_enqueued_job(Positions::RebuildJob)
  end

  it "rebuilds every active pair via .all" do
    other = create(:security, ticker: "OTH1")
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 1, cost_usd: 100)
    create(:investment_transaction, account: account, security: other,
           transaction_type: purchase_type, quantity: 2, cost_usd: 200)

    described_class.all(household: Current.household)
    expect(Position.count).to eq(2)
  end

  it "rebuilds in a fixed number of reads however many pairs there are" do
    rebuild = lambda do
      count_queries { described_class.all(household: Current.household) }.grep(/\A\s*SELECT/i).size
    end
    create(:investment_transaction, account: account, security: security,
           transaction_type: purchase_type, quantity: 1, cost_usd: 100)
    few = rebuild.call

    3.times do |i|
      create(:investment_transaction, account: create(:account), security: create(:security, ticker: "MANY#{i}"),
             transaction_type: purchase_type, quantity: 1, cost_usd: 100)
    end

    expect(rebuild.call).to eq(few)
    expect(Position.count).to eq(4)
  end
end
