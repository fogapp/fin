# typed: true

# Detects and clears semaphores that are locked (value = 0) but have no
# ClaimedExecution holding them. This happens when a worker process is
# OOM-killed or crashes hard mid-job — the ClaimedExecution is cleaned up by
# the supervisor but the semaphore decrement is never reversed, permanently
# blocking every subsequent job that shares the same concurrency key.
#
# Runs every 5 minutes via recurring.yml. Safe to run concurrently (each
# iteration is independent) and idempotent.
class OrphanedConcurrencySweepJob < ApplicationJob
  queue_as :default

  def perform
    orphaned = 0
    unblocked = 0

    SolidQueue::Semaphore.where(value: 0).find_each do |semaphore|
      # A semaphore is orphaned if no ClaimedExecution holds its key.
      held = SolidQueue::ClaimedExecution
               .joins(:job)
               .where(solid_queue_jobs: { concurrency_key: semaphore.key })
               .exists?
      next if held

      # Clear the orphaned lock so blocked executions can flow through.
      semaphore.destroy
      orphaned += 1

      # Promote up to `concurrency_limit` blocked executions back to ready.
      # BlockedExecution#release re-acquires the (now-absent) semaphore and
      # moves the job to ReadyExecution; subsequent ones stay blocked until
      # the slot opens again naturally.
      SolidQueue::BlockedExecution
        .joins(:job)
        .where(solid_queue_jobs: { concurrency_key: semaphore.key })
        .order(:id)
        .limit(1)
        .each do |blocked|
          blocked.release
          unblocked += 1
        end
    end

    if orphaned > 0
      Rails.logger.warn(
        "[OrphanedConcurrencySweepJob] Cleared #{orphaned} orphaned semaphore(s), " \
        "unblocked #{unblocked} execution(s)"
      )
      Activity.record(
        source:   "job",
        event:    "concurrency.orphaned_semaphore_cleared",
        severity: Severity::Warning,
        summary:  "Cleared #{orphaned} orphaned concurrency semaphore(s) — #{unblocked} job(s) unblocked",
        payload:  { orphaned_semaphores: orphaned, unblocked_executions: unblocked },
        household_id: Household.first&.id
      )
    end
  end
end
