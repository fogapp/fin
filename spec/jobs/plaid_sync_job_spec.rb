require "rails_helper"

RSpec.describe PlaidSyncJob, type: :job do
  include ActiveJob::TestHelper

  let(:plaid_item)    { create(:plaid_item) }
  let(:plaid_account) { create(:plaid_account, plaid_item: plaid_item) }
  let(:syncer)        { instance_double(PlaidSyncer, call: PlaidSyncer::Result.new(added: 0, modified: 0, removed: 0, errors: [], sub_errors: [])) }

  before { allow(PlaidSyncer).to receive(:new).and_return(syncer) }

  def plaid_error(body)
    Plaid::ApiError.new.tap do |error|
      allow(error).to receive(:response_body).and_return(body.to_json)
    end
  end

  it "syncs the specified item" do
    described_class.perform_now(plaid_item.id)
    expect(PlaidSyncer).to have_received(:new).with(plaid_item, only_account: nil)
    expect(syncer).to have_received(:call)
  end

  it "syncs a specific account when plaid_account_id is provided" do
    described_class.perform_now(plaid_item.id, plaid_account.id)
    expect(PlaidSyncer).to have_received(:new).with(plaid_item, only_account: plaid_account)
  end

  describe "no-arg fan-out" do
    it "enqueues one per-item job per active item instead of syncing inline" do
      item2 = create(:plaid_item, status: "active")
      plaid_item # realize the let

      expect { described_class.perform_now }
        .to have_enqueued_job(described_class).with(plaid_item.id)
        .and have_enqueued_job(described_class).with(item2.id)
      expect(PlaidSyncer).not_to have_received(:new)
    end

    it "does not enqueue jobs for inactive items" do
      create(:plaid_item, status: "error")
      expect { described_class.perform_now }.not_to have_enqueued_job(described_class)
    end
  end

  describe "error handling" do
    it "lets retriable Plaid errors propagate so retry_on engages" do
      allow(syncer).to receive(:call).and_raise(
        plaid_error(error_type: "RATE_LIMIT_EXCEEDED", error_code: "TRANSACTIONS_LIMIT")
      )

      # perform_now runs through retry_on, which re-enqueues instead of raising.
      expect { described_class.perform_now(plaid_item.id) }
        .to have_enqueued_job(described_class).with(plaid_item.id)
    end

    it "re-raises retriable Plaid errors once attempts are exhausted" do
      error = plaid_error(error_type: "API_ERROR", error_code: "INTERNAL_SERVER_ERROR")
      allow(syncer).to receive(:call).and_raise(error)

      perform_enqueued_jobs do
        expect { described_class.perform_later(plaid_item.id) }.to raise_error(Plaid::ApiError)
      end
    end

    it "discards non-retriable Plaid errors (user must re-link)" do
      allow(syncer).to receive(:call).and_raise(
        plaid_error(error_type: "ITEM_ERROR", error_code: "ITEM_LOGIN_REQUIRED",
                    error_message: "the login details of this item have changed")
      )

      expect { described_class.perform_now(plaid_item.id) }.not_to raise_error
      expect { described_class.perform_now(plaid_item.id) }
        .not_to have_enqueued_job(described_class)
    end

    it "retries non-Plaid errors via the ApplicationJob baseline instead of failing on attempt 1" do
      allow(syncer).to receive(:call).and_raise(StandardError, "boom")

      # ApplicationJob's retry_on StandardError catches the error and
      # re-enqueues; after 3 attempts it re-raises to the queue backend.
      expect { described_class.perform_now(plaid_item.id) }
        .to have_enqueued_job(described_class).with(plaid_item.id)

      perform_enqueued_jobs do
        expect { described_class.perform_later(plaid_item.id) }.to raise_error(StandardError, "boom")
      end
    end

    describe "missing Plaid credentials" do
      before do
        allow(PlaidSyncer).to receive(:new).and_raise(PlaidClient::NotConfigured.new)
      end

      def not_configured_issue
        Current.set(household: plaid_item.household) { Issue.active.find_by(key: "plaid_not_configured") }
      end

      it "raises an issue instead of failing or retrying" do
        expect { described_class.perform_now(plaid_item.id) }.not_to have_enqueued_job(described_class)

        issue = not_configured_issue
        expect(issue).to have_attributes(severity: Severity::Error, source: "plaid",
                                         body: PlaidClient::NotConfigured.new.message)
      end

      it "resolves the issue once a sync succeeds" do
        described_class.perform_now(plaid_item.id)
        allow(PlaidSyncer).to receive(:new).and_return(syncer)

        described_class.perform_now(plaid_item.id)
        expect(not_configured_issue).to be_nil
      end
    end

    it "no-ops when the item no longer exists" do
      expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
      expect(PlaidSyncer).not_to have_received(:new)
    end
  end
end
