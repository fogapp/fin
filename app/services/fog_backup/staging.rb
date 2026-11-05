# typed: strict
# frozen_string_literal: true

module FogBackup
  # Path conventions for the fog-backup contract (fog:docs/backup-contract.md).
  #
  # Everything lives under storage/fog — on a fog deploy the storage volume is
  # the app's first managed volume, so staged artifacts and the arming marker
  # survive container replacement. The producer excludes this subtree from the
  # artifact so a backup never contains staged backups.
  #
  # Fin has no JobRun model, so producer job state is file-based: each job
  # directory carries a status.json walked running → completed/failed, which
  # is all fog's polling contract needs.
  module Staging
    extend T::Sig

    STALE_AFTER = T.let(24.hours, ActiveSupport::Duration)

    # Who asked for a job. Fog collects and deletes what it triggers; a
    # manual job (Settings → Backup) belongs to the person who will download
    # it, so fog's clean-up leaves it alone.
    ORIGIN_FOG = T.let("fog", String)
    ORIGIN_MANUAL = T.let("manual", String)

    # Facts recorded when a job is triggered and carried through every later
    # status write: the origin above, who requested it, and the address the
    # request arrived on (the producer has no request to read it from).
    META_KEYS = T.let(%w[origin requested_by host rp_id].freeze, T::Array[String])

    sig { returns(Pathname) }
    def self.root = Rails.root.join("storage", "fog")

    # ---- producer side ----

    sig { returns(Pathname) }
    def self.backup_root = root.join("backup")

    sig { params(job_id: String).returns(Pathname) }
    def self.job_dir(job_id) = backup_root.join(job_id)

    sig { params(job_id: String).returns(Pathname) }
    def self.artifact_path(job_id) = job_dir(job_id).join("artifact.tar")

    sig { params(job_id: String).returns(Pathname) }
    def self.artifact_info_path(job_id) = job_dir(job_id).join("artifact.json")

    sig { params(job_id: String).returns(T.nilable(T::Hash[String, T.untyped])) }
    def self.artifact_info(job_id)
      read_json(artifact_info_path(job_id))
    end

    sig { params(job_id: String).returns(Pathname) }
    def self.status_path(job_id) = job_dir(job_id).join("status.json")

    sig { params(job_id: String).returns(T.nilable(T::Hash[String, T.untyped])) }
    def self.status(job_id)
      read_json(status_path(job_id))
    end

    sig do
      params(job_id: String, status: String, progress: T.nilable(String), error: T.nilable(String),
        meta: T::Hash[String, T.nilable(String)]).void
    end
    def self.write_status(job_id, status, progress: nil, error: nil, meta: {})
      job_dir(job_id).mkpath
      existing = self.status(job_id) || {}
      status_path(job_id).write(JSON.generate(
        existing.merge(meta).select { |key, _| META_KEYS.include?(key) }.compact.merge(
          "status" => status,
          "progress" => progress,
          "error" => error,
          "started_at" => existing["started_at"] || Time.current.utc.iso8601,
          "updated_at" => Time.current.utc.iso8601
        )
      ))
    end

    # Every job of one origin, newest first, as [job_id, status] pairs.
    # Producer workdirs (<job>.tmp) carry no status.json and drop out.
    sig { params(origin: String).returns(T::Array[[ String, T::Hash[String, T.untyped] ]]) }
    def self.jobs(origin:)
      return [] unless backup_root.exist?

      found = backup_root.children.filter_map do |dir|
        state = read_json(dir.join("status.json"))
        next nil unless state && job_origin(state) == origin

        [ dir.basename.to_s, state ]
      end
      found.sort_by { |(_, state)| state["started_at"].to_s }.reverse
    end

    # Jobs written before origins existed were all fog's.
    sig { params(state: T::Hash[String, T.untyped]).returns(String) }
    def self.job_origin(state) = state["origin"].presence || ORIGIN_FOG

    # The running producer job, if any: a `running` status younger than the
    # stale window. Anything older is presumed orphaned by a dead process.
    sig { returns(T.nilable(String)) }
    def self.active_job_id
      return nil unless backup_root.exist?

      backup_root.children.filter_map do |dir|
        state = read_json(dir.join("status.json"))
        next nil unless state && state["status"] == "running"

        started = Time.zone.parse(state["started_at"].to_s)
        next nil if started.nil? || started < 2.hours.ago

        dir.basename.to_s
      end.first
    end

    sig { void }
    def self.sweep_stale!
      return unless backup_root.exist?

      backup_root.children.each do |dir|
        FileUtils.rm_rf(dir) if dir.mtime < STALE_AFTER.ago
      rescue Errno::ENOENT
        nil # already gone — a concurrent sweep or DELETE won the race
      end
    end

    # ---- restore side ----

    sig { returns(Pathname) }
    def self.restore_root = root.join("restore")

    sig { returns(Pathname) }
    def self.pending_artifact = restore_root.join("pending.tar")

    sig { returns(Pathname) }
    def self.pending_marker = restore_root.join("pending.json")

    sig { returns(Pathname) }
    def self.receipt_path = restore_root.join("receipt.json")

    sig { returns(Pathname) }
    def self.work_dir = restore_root.join("work")

    sig { returns(T::Boolean) }
    def self.armed?
      return false unless pending_marker.exist? && pending_artifact.exist?

      (read_json(pending_marker) || {})["armed"] == true
    end

    # `rp_id` is the address the staging request arrived on, for instances
    # that derive their WebAuthn RP ID from the request rather than the
    # environment — restore-on-boot has no request to ask.
    sig { params(confirm_identity: T::Boolean, staged_by: String, rp_id: T.nilable(String)).void }
    def self.arm!(confirm_identity:, staged_by:, rp_id: nil)
      restore_root.mkpath
      pending_marker.write(JSON.pretty_generate({
        armed: true,
        confirm_identity: confirm_identity,
        staged_by: staged_by,
        staged_at: Time.current.iso8601,
        rp_id: rp_id
      }.compact))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def self.marker
      read_json(pending_marker) || {}
    end

    sig { void }
    def self.disarm!
      FileUtils.rm_f(pending_marker)
      FileUtils.rm_f(pending_artifact)
      FileUtils.rm_rf(work_dir)
    end

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    def self.receipt
      read_json(receipt_path)
    end

    sig { params(path: Pathname).returns(T.nilable(T::Hash[String, T.untyped])) }
    def self.read_json(path)
      return nil unless path.exist?

      JSON.parse(path.read)
    rescue JSON::ParserError
      nil
    end
    private_class_method :read_json
  end
end
