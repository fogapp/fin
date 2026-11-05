# typed: true

class ApplicationJob < ActiveJob::Base
  extend T::Sig

  # Baseline safety net: transient failures (network blips, provider 5xx,
  # brief DB contention) get a couple of retries with backoff instead of
  # failing permanently on attempt 1. Subclasses that register their own
  # retry_on/discard_on take precedence — rescue handlers are matched most
  # recently registered first, and a subclass's handlers are registered after
  # (therefore checked before) these.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Errors that re-running cannot fix. The blanket retry above exists for
  # network blips and provider hiccups; a NameError is a bug, and a
  # RecordInvalid means the data itself is rejected. Retrying either just
  # delays the report by two rounds of polynomial backoff — and for any job
  # whose work isn't perfectly idempotent, replays the side effects it managed
  # before raising. Registered after the blanket retry deliberately: handlers
  # match most-recently-registered first, so these win over it.
  #
  # after_discard still fires, so a bug lands in the activity timeline on the
  # first failure instead of several minutes later.
  discard_on NameError    # covers NoMethodError
  discard_on TypeError
  discard_on ActiveRecord::RecordInvalid

  # ── Trace propagation ──────────────────────────────────────────────────────
  # The enqueuer's Current.trace_id rides along in the job payload, so a whole
  # job graph (sync → dispatch → run → chained runs) shares one trace. Jobs
  # with no inherited trace (cron entry points) mint their own.

  def serialize
    super.merge("trace_id" => Current.trace_id)
  end

  def deserialize(job_data)
    super
    @inherited_trace_id = job_data["trace_id"]
  end

  around_perform do |job, block|
    Current.trace_id ||= job.instance_variable_get(:@inherited_trace_id) || SecureRandom.uuid
    block.call
  end

  # Every job runs in the instance time zone (InstanceSetting.time_zone), so
  # "today", month boundaries and snapshot days match what requests see —
  # the worker's boot default (config.time_zone) is only a fallback.
  around_perform do |_job, block|
    Time.use_zone(InstanceSetting.time_zone) { block.call }
  end

  # Sweep helper for cron jobs that fan out over every household: sets
  # Current.household and isolates failures per household. Without the
  # rescue, one bad household aborts the sweep — and the blanket retry_on
  # above then replays every already-swept household's side effects (metered
  # provider calls included) twice more. Use this instead of hand-rolling
  # Household.find_each + Current.set.
  #
  # `reraise:` lists error classes that are sweep-wide rather than
  # per-household (e.g. a provider rate limit) — those propagate so the job's
  # retry_on can back off instead of burning through the remaining households.
  # `scope:` narrows the sweep (e.g. to one household).
  def each_household(scope: Household.all, reraise: [])
    scope.find_each do |household|
      Current.set(household: household) { yield household }
    rescue StandardError => e
      raise if reraise.any? { |klass| e.is_a?(klass) }

      Rails.logger.error("[#{self.class.name}] household=#{household.id} failed: #{e.class}: #{e.message}")
    end
  end

  # Prologue for per-record jobs: unscoped find (the row may belong to a
  # household Current isn't set to yet), silently bail when the record or its
  # household is gone (the job simply outlived its subject), then run the work
  # under Current.set(household:). Use this instead of hand-rolling the same
  # find_by / return / Current.set opening in each job.
  sig { params(klass: T.untyped, id: T.untyped, blk: T.proc.params(record: T.untyped).returns(T.untyped)).void }
  def with_record(klass, id, &blk)
    record = klass.unscoped.find_by(id: id)
    return unless record

    household = Household.find_by(id: record.household_id)
    return unless household

    Current.set(household: household) { yield record }
  end

  # Prologue for per-household jobs: runs the work under
  # Current.set(household:), or logs and returns when the household is gone
  # — the job outlived it, and retrying can't bring it back (Household.find
  # used to burn three retries and then record a job.failed).
  sig { params(id: T.untyped, blk: T.proc.params(household: Household).returns(T.untyped)).void }
  def with_household(id, &blk)
    household = Household.find_by(id: id)
    unless household
      Rails.logger.warn("[#{self.class.name}] household=#{id} no longer exists; skipping")
      return
    end

    Current.set(household: household) { yield household }
  end

  # Jobs that are done retrying (retry_on attempts exhausted, or matched a
  # discard_on) surface in the activity timeline with severity error. Using
  # after_discard instead of rescuing in around_perform means intermediate
  # retry attempts stay quiet — only the final, permanent failure is recorded.
  # Most jobs set Current.household inside perform, which has unwound by the
  # time we get here, so an unattributable failure is recorded for every
  # household — a permanently dead job is system-wide news.
  after_discard do |job, error|
    household_ids = Current.household ? [ Current.household.id ] : Household.pluck(:id)
    household_ids.each do |household_id|
      Activity.record(
        source:   "job",
        event:    "job.failed",
        severity: Severity::Error,
        summary:  "#{job.class.name} failed: #{error.class}: #{error.message}",
        payload:  { job_class: job.class.name, queue: job.queue_name, executions: job.executions },
        household_id: household_id
      )
    end
  end
end
