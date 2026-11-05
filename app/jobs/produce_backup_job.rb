# typed: strict
# frozen_string_literal: true

# Produces one fog-backup/2 artifact into staging (fog:docs/backup-contract.md).
# Triggered by fog's POST /fog/backup (FogBackup::Trigger); fog polls the
# file-based job status and downloads the result.
class ProduceBackupJob < ApplicationJob
  extend T::Sig

  queue_as :backup

  # Fail fast: fog is polling for a verdict, and a dump that failed once
  # fails the same way on retry — each retry costing a full pg_dump.
  retry_on StandardError, attempts: 1

  # A second dump racing the first would double disk under staging and
  # thrash the database for nothing.
  limits_concurrency to: 1, key: "produce_backup", duration: 2.hours

  sig { params(job_id: String).void }
  def perform(job_id)
    FogBackup::Staging.write_status(job_id, "running", progress: "starting")
    message = FogBackup::Producer.new(job_id: job_id).call
    FogBackup::Staging.write_status(job_id, "completed", progress: message)
    Lucid.event("Backup produced", tags: { mode: "fog" })
  rescue StandardError => e
    FogBackup::Staging.write_status(job_id, "failed", error: "#{e.class}: #{e.message}".truncate(1000))
    Activity.record(
      source: "fog", event: "backup.produce.failed", severity: Severity::Error,
      summary: "Backup artifact production failed: #{e.class}: #{e.message.to_s.truncate(200)}"
    )
    raise
  end
end
