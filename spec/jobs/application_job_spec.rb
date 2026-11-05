require "rails_helper"

RSpec.describe ApplicationJob, type: :job do
  before do
    stub_const("RetryProbeJob", Class.new(ApplicationJob) do
      queue_as :default

      def perform
        raise "kaboom"
      end
    end)
  end

  describe "baseline StandardError retry" do
    it "retries instead of failing permanently on the first attempt, staying quiet in the activity feed" do
      expect { RetryProbeJob.perform_now }.to have_enqueued_job(RetryProbeJob)

      expect(ActivityEntry.where(event: "job.failed")).to be_empty
    end

    it "records a single job.failed activity only once retries are exhausted" do
      perform_enqueued_jobs do
        expect { RetryProbeJob.perform_later }.to raise_error(RuntimeError, "kaboom")
      end

      entry = ActivityEntry.where(event: "job.failed").sole
      expect(entry.severity).to eq(Severity::Error)
      expect(entry.summary).to include("RetryProbeJob")
      expect(entry.summary).to include("kaboom")
    end
  end

  describe "errors a retry cannot fix" do
    before do
      stub_const("BugProbeJob", Class.new(ApplicationJob) do
        queue_as :default

        def perform
          nil.this_method_does_not_exist
        end
      end)

      stub_const("InvalidProbeJob", Class.new(ApplicationJob) do
        queue_as :default

        def perform
          raise ActiveRecord::RecordInvalid.new(Merchant.new)
        end
      end)
    end

    it "discards a NoMethodError on the first attempt instead of retrying it" do
      expect { BugProbeJob.perform_now }.not_to have_enqueued_job(BugProbeJob)
    end

    it "reports the bug in the activity feed immediately, not after backoff" do
      BugProbeJob.perform_now

      entry = ActivityEntry.where(event: "job.failed").sole
      expect(entry.severity).to eq(Severity::Error)
      expect(entry.summary).to include("BugProbeJob")
      expect(entry.summary).to include("NoMethodError")
    end

    it "discards a RecordInvalid rather than replaying a rejected write" do
      expect { InvalidProbeJob.perform_now }.not_to have_enqueued_job(InvalidProbeJob)
      expect(ActivityEntry.where(event: "job.failed").count).to eq(1)
    end

    it "still retries an ordinary transient failure" do
      expect { RetryProbeJob.perform_now }.to have_enqueued_job(RetryProbeJob)
    end
  end

  describe "subclass handler precedence" do
    it "lets a subclass retry_on win over the baseline (PlaidSyncJob retries Plaid::ApiError 5 times)" do
      handler = PlaidSyncJob.rescue_handlers.reverse.find { |klass, _| klass == "Plaid::ApiError" }
      expect(handler).to be_present

      # The baseline StandardError handler is registered before (and therefore
      # matched after) any subclass handler.
      expect(PlaidSyncJob.rescue_handlers.map(&:first)).to include("StandardError", "Plaid::ApiError")
      expect(PlaidSyncJob.rescue_handlers.map(&:first).index("StandardError"))
        .to be < PlaidSyncJob.rescue_handlers.map(&:first).index("Plaid::ApiError")
    end
  end

  describe "#each_household" do
    before do
      stub_const("SweepProbeJob", Class.new(ApplicationJob) do
        queue_as :default

        cattr_accessor :visited, default: []

        def perform
          each_household do |household|
            raise "bad household" if household.name == "Broken"

            self.class.visited << [ household.id, Current.household&.id ]
          end
        end
      end)
    end

    it "sets Current.household and isolates a failing household from the rest of the sweep" do
      first  = Current.household
      broken = create(:household, name: "Broken")
      last   = create(:household, name: "After")

      expect { SweepProbeJob.perform_now }.not_to raise_error

      visited_ids = SweepProbeJob.visited.map(&:first)
      expect(visited_ids).to include(first.id, last.id)
      expect(visited_ids).not_to include(broken.id)
      # Current.household was set to each swept household inside the block.
      SweepProbeJob.visited.each { |id, current_id| expect(current_id).to eq(id) }
    end
  end

  describe "#with_record" do
    before do
      stub_const("RecordProbeJob", Class.new(ApplicationJob) do
        queue_as :default

        cattr_accessor :seen, default: []

        def perform(merchant_id)
          with_record(Merchant, merchant_id) do |merchant|
            self.class.seen << [ merchant.id, Current.household&.id ]
          end
        end
      end)
    end

    it "yields the record with Current.household set to the record's household" do
      other    = create(:household, name: "Elsewhere")
      merchant = Current.set(household: other) { create(:merchant) }

      RecordProbeJob.perform_now(merchant.id)

      expect(RecordProbeJob.seen).to eq([ [ merchant.id, other.id ] ])
    end

    it "silently no-ops when the record no longer exists" do
      RecordProbeJob.perform_now(SecureRandom.uuid)

      expect(RecordProbeJob.seen).to be_empty
    end
  end

  describe "#with_household" do
    before do
      stub_const("HouseholdProbeJob", Class.new(ApplicationJob) do
        queue_as :default

        cattr_accessor :seen, default: []

        def perform(household_id)
          with_household(household_id) do |household|
            self.class.seen << [ household.id, Current.household&.id ]
          end
        end
      end)
    end

    it "yields the household with Current.household set to it" do
      other = create(:household, name: "Elsewhere")

      HouseholdProbeJob.perform_now(other.id)

      expect(HouseholdProbeJob.seen).to eq([ [ other.id, other.id ] ])
    end

    it "logs and skips a household that no longer exists instead of retrying" do
      expect { HouseholdProbeJob.perform_now(SecureRandom.uuid) }.not_to have_enqueued_job(HouseholdProbeJob)

      expect(HouseholdProbeJob.seen).to be_empty
    end
  end
end
