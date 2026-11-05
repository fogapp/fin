require "rails_helper"

RSpec.describe SystemAuditJob, type: :job do
  describe "failed background job watchdog" do
    def failed_execution(class_name:)
      job = SolidQueue::Job.create!(
        queue_name:    "default",
        class_name:    class_name,
        arguments:     [],
        active_job_id: SecureRandom.uuid
      )
      SolidQueue::FailedExecution.create!(job: job, error: "boom")
    end

    before { SolidQueue::FailedExecution.delete_all }

    it "raises an error-severity issue naming the failing job classes" do
      failed_execution(class_name: "PlaidSyncJob")
      failed_execution(class_name: "PlaidSyncJob")
      failed_execution(class_name: "MarketPriceSyncJob")

      described_class.perform_now

      issue = Issue.find_by!(key: "solid_queue_failed_jobs")
      expect(issue.severity).to eq(Severity::Error)
      expect(issue.title).to include("3")
      expect(issue.body).to include("PlaidSyncJob ×2")
      expect(issue.body).to include("MarketPriceSyncJob ×1")

      entry = ActivityEntry.where(event: "jobs.failed_executions").sole
      expect(entry.severity).to eq(Severity::Error)
    end

    it "resolves the issue once the failed executions are cleared" do
      failed_execution(class_name: "PlaidSyncJob")
      described_class.perform_now

      SolidQueue::FailedExecution.delete_all
      described_class.perform_now

      expect(Issue.find_by!(key: "solid_queue_failed_jobs").dismissed_at).to be_present
      expect(Issue.active.where(key: "solid_queue_failed_jobs")).to be_empty
    end
  end

  describe "duplicate holdings watchdog" do
    let(:account) { create(:account) }

    def plaid_snap(security, as_of:)
      create(:position_snapshot, security: security, account: account, as_of_date: as_of,
                                 source_row_hash: "plaid_holding:#{account.id}:#{security.id}:#{as_of}")
    end

    # The resolver-era row Plaid still syncs, and the one it abandoned.
    def forked_holding(name)
      keep = create(:security, name: name, ticker: nil, cusip: nil)
      Instruments::Resolver.register!(keep, { "plaid_security_id" => "plaid-#{keep.id}" })
      plaid_snap(keep, as_of: Date.current)

      abandoned = create(:security, name: name, ticker: nil, cusip: nil)
      InstrumentIdentifier.unscoped.where(security_id: abandoned.id).delete_all
      plaid_snap(abandoned, as_of: 1.month.ago.to_date)
      [ keep, abandoned ]
    end

    it "raises an error-severity issue naming the split holdings" do
      forked_holding("Hps Corporate Lending Fund")

      described_class.perform_now

      issue = Issue.find_by!(key: "duplicate_plaid_securities")
      expect(issue.severity).to eq(Severity::Error)
      expect(issue.title).to include("1 holding")
      expect(issue.body).to include("Hps Corporate Lending Fund")
      expect(issue.body).to include("instruments:plaid_duplicates")
    end

    it "resolves once the duplicates are merged" do
      keep, abandoned = forked_holding("Hps Corporate Lending Fund")
      described_class.perform_now
      expect(Issue.active.find_by(key: "duplicate_plaid_securities")).to be_present

      Instruments::Merge.call(keep: keep, remove: abandoned)
      described_class.perform_now

      expect(Issue.active.where(key: "duplicate_plaid_securities")).to be_empty
    end

    it "stays quiet when every holding maps to one security" do
      described_class.perform_now
      expect(Issue.where(key: "duplicate_plaid_securities")).to be_empty
    end
  end
end
