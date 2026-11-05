# typed: strict
# frozen_string_literal: true

module FogBackup
  # Restore-on-boot (fog:docs/backup-contract.md): consume the staged, armed
  # artifact before the app serves traffic. Invoked from fog:release (fog's
  # release phase) and from the docker entrypoint guard. Exactly one process
  # restores — everything runs under a session-level Postgres advisory lock.
  #
  # pg_restore runs as the app's own database role, so every restored object
  # is owned correctly — no post-restore REASSIGN OWNED fix-up.
  #
  # Fin-specific: the single database means the dump carries solid_queue
  # and solid_cache rows. Restoring stale claimed executions resurrects
  # wreckage (the orphan sweepers exist precisely for that), so those tables
  # are truncated after the restore — the queue starts empty, the recurring
  # schedule repopulates it.
  class Restorer
    extend T::Sig

    class Error < StandardError; end

    RESTORE_TIMEOUT = T.let(3600 * 2, Integer)
    LOCK_KEY = T.let("fog_backup_restore", String)

    sig { returns(T::Boolean) }
    def self.run_if_armed!
      return false unless Staging.armed?

      new.call
    end

    # The lock lives on a connection of its own. A session-level advisory
    # lock dies with its session, and the restore reconnects the main
    # connection once the schema has been replaced under it — holding the
    # lock there released it mid-restore, letting a sibling (web and worker
    # both run the boot guard) start a second pg_restore over the first.
    sig { returns(T::Boolean) }
    def call
      pool = ActiveRecord::Base.connection_pool
      lock = pool.checkout
      lock.execute("SELECT pg_advisory_lock(hashtext(#{lock.quote(LOCK_KEY)}))")
      begin
        # Re-check under the lock: a sibling process may have finished the
        # restore while this one waited.
        return false unless Staging.armed?

        restore!
        true
      ensure
        lock.execute("SELECT pg_advisory_unlock(hashtext(#{lock.quote(LOCK_KEY)}))")
        pool.checkin(lock)
      end
    end

    private

    sig { void }
    def restore!
      marker = Staging.marker
      rp_id = marker["rp_id"]&.to_s.presence
      forget = marker["forget_secrets"] == true
      preflight = Preflight.check(
        artifact_path: Staging.pending_artifact,
        confirm_identity: marker["confirm_identity"] == true,
        rp_id: rp_id,
        forget_secrets: forget
      )
      unless preflight.ok?
        # The marker stays armed: a half-diagnosed restore must block boot
        # loudly, not fall through to serving an empty instance.
        raise Error, "Restore preflight failed:\n  #{preflight.errors.join("\n  ")}"
      end
      manifest = T.must(preflight.manifest)

      work = Staging.work_dir
      FileUtils.rm_rf(work)
      work.mkpath

      extract_artifact(work)
      restore_primary(work, manifest)
      truncate_queue_and_cache
      restore_files(work, manifest)
      forgotten = forget ? ForgetSecrets.run! : {}
      move = AddressChange.detect(manifest, current_rp: Manifest.current_rp_id(fallback: rp_id))
      write_receipt(manifest, move, forgotten)
      record_completion(manifest, move, forgotten)
      Staging.disarm!
    end

    # Activity rows are household-scoped and a restore is instance-wide, so
    # the restored households each get the entry — there is no request (and
    # so no current household) at boot. Best-effort: the data is already
    # back, and a timeline row must not turn that into a failed restore.
    sig do
      params(manifest: Manifest::Parsed, move: T.nilable(AddressChange::Move),
        forgotten: T::Hash[String, T::Array[String]]).void
    end
    def record_completion(manifest, move, forgotten)
      summary = "Restored from artifact created #{manifest.created_at} (#{manifest.git_sha&.first(12)})"
      summary += " — moved from #{move.from} to #{move.to}" if move
      summary += " — without its original secrets: saved credentials need entering again and linked institutions linking again" if forgotten.any?
      Lucid.event("Backup restored", tags: { moved: move ? "true" : "false" })
      Household.find_each do |household|
        Activity.record(source: "fog", event: "backup.restore.completed", summary: summary, household_id: household.id)
      end
    rescue StandardError => e
      Rails.logger.warn("[fog] could not record the restore on the activity log: #{e.class}: #{e.message}")
    end

    sig { params(work: Pathname).void }
    def extract_artifact(work)
      run!([ "tar", "-xf", Staging.pending_artifact.to_s, "-C", work.to_s ])
    end

    # A component's file, at the path its manifest entry names — never a
    # path assumed from the format, so every format this app ever wrote
    # restores. The path must stay inside the extracted artifact.
    sig { params(work: Pathname, component: T::Hash[String, T.untyped]).returns(Pathname) }
    def component_file(work, component)
      path = component["path"].to_s
      file = work.join(path).expand_path
      root = work.expand_path
      unless path.present? && file.to_s.start_with?("#{root}/")
        raise Error, "Component #{component["name"].inspect} names a path outside the artifact: #{path.inspect}"
      end

      file
    end

    sig { params(work: Pathname, manifest: Manifest::Parsed).void }
    def restore_primary(work, manifest)
      entry = manifest.primary
      raise Error, "Artifact's manifest lists no primary database component" if entry.nil?

      dump = component_file(work, entry)
      raise Error, "Artifact has no #{entry["path"]}" unless dump.exist?

      drop_own_tables
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      toc = restorable_toc(dump)
      run!([
        "pg_restore", "--clean", "--if-exists", "--no-owner", "--no-privileges",
        "--use-list", toc.to_s,
        "-h", config[:host].to_s,
        "-p", (config[:port] || 5432).to_s,
        "-U", config[:username].to_s,
        "-d", config[:database].to_s,
        dump.to_s
      ], env: { "PGPASSWORD" => config[:password].to_s })
      ActiveRecord::Base.connection.schema_cache.clear!
      ActiveRecord::Base.connection.reconnect!
    end

    # The dump's table of contents without its extensions. Fog creates those
    # as its own admin role when it provisions the database, so the app's
    # role can neither drop them (--clean) nor create them — and need not:
    # they are already there before the first boot.
    EXTENSION_ENTRY = T.let(/\A\d+; \d+ \d+ (?:EXTENSION|COMMENT - EXTENSION) /, Regexp)

    # Written to a file rather than read from stdout, which Shell caps — a
    # truncated list would restore only part of the database, silently.
    sig { params(dump: Pathname).returns(Pathname) }
    def restorable_toc(dump)
      toc = dump.sub_ext(".toc")
      run!([ "pg_restore", "--list", "--file", toc.to_s, dump.to_s ])
      toc.write(toc.each_line.grep_v(EXTENSION_ENTRY).join)
      toc
    end

    # The dump carried the source instance's queue and cache state. Stale
    # claimed executions would replay or strand jobs; the cache regenerates.
    sig { void }
    def truncate_queue_and_cache
      connection = ActiveRecord::Base.connection
      tables = connection.select_values(<<~SQL)
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public'
          AND (tablename LIKE 'solid_queue_%' OR tablename = 'solid_cache_entries')
      SQL
      return if tables.empty?

      quoted = tables.map { |t| connection.quote_table_name(t) }.join(", ")
      connection.execute("TRUNCATE #{quoted} CASCADE")
    end

    # pg_restore --clean drops only what the dump contains. An artifact from
    # older code restored into a newer install meets tables the dump has
    # never heard of, and one with a foreign key into a restored table blocks
    # that table's drop — the restore fails on every boot. So the database is
    # emptied first: every table Fin's own role owns, cascading to whatever
    # hangs off it. Extensions are fog's (its admin role creates them) and
    # are left alone; db:prepare migrates the restored schema forward
    # afterwards.
    sig { params(schema: String).void }
    def drop_own_tables(schema: "public")
      connection = ActiveRecord::Base.connection
      tables = connection.select_values(<<~SQL.squish)
        SELECT format('%I.%I', schemaname, tablename) FROM pg_tables
        WHERE schemaname = #{connection.quote(schema)} AND tableowner = current_user
      SQL
      connection.execute("DROP TABLE IF EXISTS #{tables.join(", ")} CASCADE") if tables.any?
    end

    # Each file component unpacked by its extension: fog-backup/1 wrote
    # `.tar.zst`, fog-backup/2 writes a plain `.tar`. Preflight has already
    # refused any component this cannot unpack.
    sig { params(work: Pathname, manifest: Manifest::Parsed, storage: Pathname).void }
    def restore_files(work, manifest, storage: Rails.root.join("storage"))
      manifest.file_components.each do |component|
        archive = component_file(work, component)
        raise Error, "Artifact has no #{component["path"]}" unless archive.exist?

        target = case component["name"]
        when "storage" then storage
        else raise Error, "File component #{component["name"].inspect} is not one this app restores"
        end
        codec = Preflight.archive_codec(archive.to_s)
        raise Error, "File component #{component["path"]} is neither a .tar nor a .tar.zst" if codec.nil?

        target.mkpath
        argv = codec == :zstd ? [ "tar", "--zstd", "-xf" ] : [ "tar", "-xf" ]
        run!(argv + [ archive.to_s, "-C", target.to_s ])
      end
    end

    sig do
      params(manifest: Manifest::Parsed, move: T.nilable(AddressChange::Move),
        forgotten: T::Hash[String, T::Array[String]]).void
    end
    def write_receipt(manifest, move, forgotten)
      Staging.restore_root.mkpath
      Staging.receipt_path.write(JSON.pretty_generate({
        restored_at: Time.current.utc.iso8601,
        artifact_created_at: manifest.created_at,
        artifact_git_sha: manifest.git_sha,
        artifact_schema_version: manifest.schema_version.to_s,
        restored_by_git_sha: ENV["GIT_SHA"].presence || "unknown",
        moved_from: move&.from,
        moved_to: move&.to,
        forgotten: forgotten.presence
      }.compact))
    end

    sig { params(argv: T::Array[String], env: T::Hash[String, String]).void }
    def run!(argv, env: {})
      result = Shell.run(argv, timeout: RESTORE_TIMEOUT, env: env)
      return if result.success?

      raise Error, "#{argv.first} exited #{result.status}: #{result.stderr.presence || result.stdout}".truncate(1000)
    end
  end
end
