# typed: true

# Retention for the observability data: routine activity entries are kept 90
# days, errors a year; finished workflow runs are kept 90 days unless they
# failed (failures stay for the error timeline until their entries expire).
# Account balance snapshots are kept 2 years.
class PruneActivityJob < ApplicationJob
  extend T::Sig

  queue_as :default

  ROUTINE_RETENTION  = 90.days
  ERROR_RETENTION    = 365.days
  SNAPSHOT_RETENTION = 2.years

  sig { void }
  def perform
    pruned_entries = ActivityEntry.unscoped
      .where.not(severity: Severity::Error)
      .where(occurred_at: ...ROUTINE_RETENTION.ago)
      .delete_all
    pruned_errors = ActivityEntry.unscoped
      .where(severity: Severity::Error)
      .where(occurred_at: ...ERROR_RETENTION.ago)
      .delete_all

    pruned_runs = 0
    WorkflowRun.unscoped
               .where(status: %w[completed cancelled])
               .where(created_at: ...ROUTINE_RETENTION.ago)
               .in_batches(of: 500) { |batch| pruned_runs += batch.destroy_all.size }

    # Balance snapshots dedupe to one row per (account, day, source) at write
    # time; retention here bounds the table's total history. delete_all skips
    # the per-row DataVersion bump on purpose — losing 2-year-old points
    # doesn't invalidate any current-facing cache meaningfully.
    pruned_snapshots = AccountBalanceSnapshot
      .where(recorded_at: ...SNAPSHOT_RETENTION.ago)
      .delete_all

    Rails.logger.info("[PruneActivityJob] entries=#{pruned_entries + pruned_errors} runs=#{pruned_runs} snapshots=#{pruned_snapshots}")
  end
end
