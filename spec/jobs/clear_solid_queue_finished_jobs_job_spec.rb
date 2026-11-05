require "rails_helper"

RSpec.describe ClearSolidQueueFinishedJobsJob, type: :job do
  def finished_job(finished_at:, class_name: "MarketPriceSyncJob")
    SolidQueue::Job.create!(
      queue_name:  "default",
      class_name:  class_name,
      arguments:   [],
      active_job_id: SecureRandom.uuid,
      finished_at: finished_at
    )
  end

  before { SolidQueue::Job.delete_all }

  it "deletes finished jobs older than retain_days" do
    old    = finished_job(finished_at: 60.days.ago)
    recent = finished_job(finished_at: 1.day.ago)

    described_class.perform_now(retain_days: 30, max_executions: 0)

    expect(SolidQueue::Job.exists?(old.id)).to    be false
    expect(SolidQueue::Job.exists?(recent.id)).to be true
  end

  it "deletes all finished rows when retain_days and max_executions are both off" do
    a = finished_job(finished_at: 1.hour.ago)
    described_class.perform_now(retain_days: 0, max_executions: 0)
    expect(SolidQueue::Job.exists?(a.id)).to be false
  end

  it "trims finished jobs beyond max_executions, keeping the newest N" do
    jobs = 5.times.map { |i| finished_job(finished_at: (10 - i).hours.ago) }

    described_class.perform_now(retain_days: 0, max_executions: 2)

    surviving = SolidQueue::Job.finished.pluck(:id)
    # The two newest finishes are the last two we created.
    expect(surviving).to contain_exactly(jobs[-1].id, jobs[-2].id)
  end

  it "falls back to deleting nothing extra when the max_executions cutoff lookup returns nil" do
    # With max_executions > row count the cutoff_time pick returns nil, so the
    # second filter is skipped entirely. retain_days here keeps the recent row
    # safe, so nothing is deleted.
    a = finished_job(finished_at: 1.hour.ago)
    described_class.perform_now(retain_days: 30, max_executions: 100)
    expect(SolidQueue::Job.exists?(a.id)).to be true
  end

  it "is enqueueable on the default queue" do
    expect { described_class.perform_later }
      .to have_enqueued_job(described_class).on_queue("default")
  end
end
