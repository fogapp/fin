# typed: strict
# frozen_string_literal: true

module FogBackup
  # JSON shapes for the fog-backup machine surface (fog:docs/backup-contract.md).
  # The consumer is fog's Go client — field names are the contract's,
  # snake_case, and stable.
  module Serializer
    extend T::Sig

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def self.descriptor_json
      {
        contract: Manifest::FORMAT,
        app: Manifest::APP,
        version: {
          git_sha: ENV["GIT_SHA"].presence || "unknown",
          schema_version: Manifest.code_schema_version.to_s
        },
        pg: Manifest.pg_info,
        components: [
          { name: "primary", kind: "db" },
          { name: "storage", kind: "files" }
        ],
        external: [],
        fresh: !User.exists?,
        last_restore: Staging.receipt&.slice("restored_at", "artifact_created_at", "artifact_git_sha"),
        estimated_bytes: estimated_bytes
      }
    end

    sig { params(job_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def self.job_json(job_id)
      state = Staging.status(job_id)
      return nil if state.nil?

      case state["status"]
      when "running"
        { status: "running", progress: state["progress"] }.compact
      when "failed"
        { status: "failed", error: state["error"].presence || "producer job failed" }
      when "completed"
        info = Staging.artifact_info(job_id)
        if info.nil?
          { status: "failed", error: "artifact is no longer staged" }
        else
          { status: "completed", artifact: { bytes: info["bytes"].to_i, sha256: info["sha256"].to_s } }
        end
      else
        { status: "failed", error: "unknown producer state #{state["status"].inspect}" }
      end
    end

    # ---- Settings → Backup (Api::V1::BackupsController) ----

    # The manual backups staged on this instance plus what a person needs to
    # know to carry one elsewhere: the address its passkeys are bound to and
    # which secrets it was encrypted with (fingerprints only — the values
    # are a separate, audited request).
    sig { params(host: String).returns(T::Hash[Symbol, T.untyped]) }
    def self.overview_json(host:)
      {
        backups: Staging.jobs(origin: Staging::ORIGIN_MANUAL).map { |(job_id, state)| backup_row(job_id, state) },
        address: { host: host, rp_id: Manifest.current_rp_id(fallback: host) },
        keys: Manifest.secrets_fingerprint.map { |name, fingerprint| { name: name, fingerprint: fingerprint } },
        retention_hours: Staging::STALE_AFTER.in_hours.to_i,
        last_restore: Staging.receipt&.slice("restored_at", "artifact_created_at", "moved_from", "moved_to")
      }
    end

    sig { params(job_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def self.backup_json(job_id)
      state = Staging.status(job_id)
      state && backup_row(job_id, state)
    end

    # One shape for every state, so the list renders without branching on
    # which keys exist. A job still "running" past the producer's own
    # deadline was orphaned by a dead worker and reads as failed.
    sig { params(job_id: String, state: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def self.backup_row(job_id, state)
      job = job_json(job_id) || {}
      status = job[:status].to_s
      error = job[:error]
      if status == "running" && Staging.active_job_id != job_id
        status = "failed"
        error = "The backup job stopped before it finished"
      end
      info = status == "completed" ? Staging.artifact_info(job_id) : nil
      created_at = info && Time.zone.parse(info["created_at"].to_s)

      {
        id: job_id,
        status: status,
        progress: status == "running" ? state["progress"] : nil,
        error: error,
        started_at: state["started_at"],
        requested_by: state["requested_by"],
        bytes: info && info["bytes"].to_i,
        sha256: info && info["sha256"].to_s,
        created_at: created_at&.utc&.iso8601,
        expires_at: created_at && (created_at + Staging::STALE_AFTER).utc.iso8601,
        filename: info && artifact_filename(job_id)
      }
    end
    private_class_method :backup_row

    # Named for when the artifact was produced, not when it was fetched —
    # two downloads of one backup are the same file.
    sig { params(job_id: String).returns(String) }
    def self.artifact_filename(job_id)
      created = Time.zone.parse((Staging.artifact_info(job_id) || {})["created_at"].to_s) || Time.current
      "fin-#{created.utc.strftime("%Y%m%d-%H%M%S")}.fogpack.tar"
    end

    sig { params(result: Preflight::Result).returns(T::Hash[Symbol, T.untyped]) }
    def self.preflight_json(result)
      {
        ok: result.ok?,
        errors: result.errors,
        warnings: result.warnings,
        artifact: result.manifest&.raw&.slice("app", "created_at", "produced_by", "identity")
      }
    end

    sig { returns(Integer) }
    def self.estimated_bytes
      db = ActiveRecord::Base.connection.select_value("SELECT pg_database_size(current_database())").to_i
      root = Rails.root.join("storage")
      storage = root.exist? ? root.glob("**/*").sum { |p| p.file? ? p.size : 0 } : 0
      db + storage
    end
  end
end
