require "rails_helper"

RSpec.describe Workflows::Events do
  let(:account) { create(:account) }

  before { described_class.reset_cache }

  it "is a no-op when no active workflow listens for the event type" do
    txn = create(:cash_transaction, :bank, account: account)

    expect {
      described_class.publish("cash_transaction.updated", subject: txn)
    }.not_to have_enqueued_job(Workflows::DispatchJob)
  end

  it "enqueues a dispatch when an active workflow listens" do
    create(:workflow, trigger_type: "cash_transaction.updated")
    described_class.reset_cache
    txn = create(:cash_transaction, :bank, account: account)

    expect {
      described_class.publish("cash_transaction.updated", subject: txn, payload: { "changes" => [ "memo" ] })
    }.to have_enqueued_job(Workflows::DispatchJob)
      .with("cash_transaction.updated", Current.household.id.to_s, "CashTransaction", txn.id.to_s, { "changes" => [ "memo" ] })
  end

  it "does not dispatch for inactive workflows" do
    create(:workflow, trigger_type: "cash_transaction.updated", active: false)
    described_class.reset_cache
    txn = create(:cash_transaction, :bank, account: account)

    expect {
      described_class.publish("cash_transaction.updated", subject: txn)
    }.not_to have_enqueued_job(Workflows::DispatchJob)
  end

  it "publishes lifecycle events from registry models via the concern" do
    create(:workflow, trigger_type: "cash_transaction.created")
    described_class.reset_cache

    expect {
      create(:cash_transaction, :bank, account: account)
    }.to have_enqueued_job(Workflows::DispatchJob).with { |type, *|
      expect(type).to eq("cash_transaction.created")
    }
  end

  it "includes changed attribute names on updated events" do
    create(:workflow, trigger_type: "cash_transaction.updated")
    described_class.reset_cache
    txn = create(:cash_transaction, :bank, account: account)

    expect {
      txn.update!(memo: "new memo")
    }.to have_enqueued_job(Workflows::DispatchJob).with { |type, _hh, _st, _sid, payload|
      expect(type).to eq("cash_transaction.updated")
      expect(payload["changes"]).to include("memo")
    }
  end
end
