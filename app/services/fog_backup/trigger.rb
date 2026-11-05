# typed: strict
# frozen_string_literal: true

module FogBackup
  # Starts (or adopts) the producer job — for fog's POST /fog/backup and for
  # a manual backup from Settings → Backup. Fin has no JobRun model, so job
  # identity is a random id and state lives in the staging directory's
  # status.json — all fog's polling contract needs.
  #
  # The advisory lock makes the check-and-start atomic: two racing POSTs (or
  # fog racing a manual trigger) contend on one lock, and the loser adopts
  # the winner's running job — fog's contract answer to "already producing"
  # is 409 + that job's id.
  module Trigger
    extend T::Sig

    class Outcome < T::Struct
      const :job_id, String
      const :started, T::Boolean
      # Who the job belongs to — the caller's own origin when it started one,
      # the running job's when it adopted.
      const :origin, String
    end

    # `host` / `rp_id` describe the address a manual request arrived on, so
    # the manifest can name where the artifact's passkeys are bound even on
    # an instance that configures nothing (see Manifest.identity).
    sig do
      params(origin: String, requested_by: T.nilable(String), host: T.nilable(String), rp_id: T.nilable(String))
        .returns(Outcome)
    end
    def self.call(origin: Staging::ORIGIN_FOG, requested_by: nil, host: nil, rp_id: nil)
      outcome = T.let(nil, T.nilable(Outcome))
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtext(#{ActiveRecord::Base.connection.quote("fog_backup_producer")}))"
        )
        if (active = Staging.active_job_id)
          running = Staging.job_origin(Staging.status(active) || {})
          outcome = Outcome.new(job_id: active, started: false, origin: running)
        else
          job_id = SecureRandom.hex(12)
          Staging.write_status(job_id, "running", progress: "queued", meta: {
            "origin" => origin, "requested_by" => requested_by, "host" => host, "rp_id" => rp_id
          })
          outcome = Outcome.new(job_id: job_id, started: true, origin: origin)
        end
      end
      result = T.must(outcome)
      ProduceBackupJob.perform_later(result.job_id) if result.started
      result
    end
  end
end
