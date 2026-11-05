# typed: strict
# frozen_string_literal: true

module FogBackup
  # Builds one fog-backup/2 artifact into producer staging
  # (fog:docs/backup-contract.md): an uncompressed custom-format pg_dump of
  # Fin's single database with the container's own binary, a plain tar of
  # the (tiny) storage tree, a manifest, and a single outer tar with the
  # manifest first. Nothing is compressed: fog's store deduplicates the
  # artifact by content and compresses each chunk itself. One dump is
  # 100% of the relational state — app data, solid_queue, solid_cache all
  # share the database; restore truncates the queue/cache tables.
  class Producer
    extend T::Sig

    class Error < StandardError; end

    DUMP_TIMEOUT = T.let(3600, Integer)
    TAR_TIMEOUT = T.let(3600, Integer)
    DUMP_PATH = T.let("db/primary.dump", String)
    STORAGE_PATH = T.let("files/storage.tar", String)

    sig { params(job_id: String).void }
    def initialize(job_id:)
      @job_id = job_id
      @workdir = T.let(Staging.backup_root.join("#{job_id}.tmp"), Pathname)
    end

    sig { returns(String) }
    def call
      Staging.sweep_stale!
      FileUtils.rm_rf(@workdir)
      @workdir.join("db").mkpath
      @workdir.join("files").mkpath

      progress("dumping database")
      dump_primary

      progress("archiving file storage")
      archive_storage

      progress("writing manifest")
      requested = Staging.status(@job_id) || {}
      manifest = Manifest.build(components: components, host: requested["host"], rp_id: requested["rp_id"])
      @workdir.join("manifest.json").write(JSON.pretty_generate(manifest))

      progress("assembling artifact")
      artifact = assemble

      "artifact #{ActiveSupport::NumberHelper.number_to_human_size(artifact[:bytes])}, sha256 #{artifact[:sha256].to_s.first(12)}"
    ensure
      FileUtils.rm_rf(@workdir)
    end

    private

    sig { params(message: String).void }
    def progress(message)
      Staging.write_status(@job_id, "running", progress: message)
    end

    sig { void }
    def dump_primary
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      argv = [
        "pg_dump", "-Fc", "-Z0", "--no-owner", "--no-privileges", "--no-comments",
        "-h", config[:host].to_s,
        "-p", (config[:port] || 5432).to_s,
        "-U", config[:username].to_s,
        "-d", config[:database].to_s,
        "-f", @workdir.join(DUMP_PATH).to_s
      ]
      run!(argv, timeout: DUMP_TIMEOUT, env: { "PGPASSWORD" => config[:password].to_s })
    end

    sig { void }
    def archive_storage
      root = Rails.root.join("storage")
      root.mkpath
      run!([
        "tar",
        "--exclude", "./fog", "--exclude", "./fog/*",
        "-cf", @workdir.join(STORAGE_PATH).to_s,
        "-C", root.to_s, "."
      ], timeout: TAR_TIMEOUT)
    end

    sig { returns(T::Array[Manifest::Component]) }
    def components
      [
        component("primary", DUMP_PATH, "db"),
        component("storage", STORAGE_PATH, "files")
      ]
    end

    sig { params(name: String, path: String, kind: String).returns(Manifest::Component) }
    def component(name, path, kind)
      file = @workdir.join(path)
      Manifest::Component.new(
        name: name, path: path, kind: kind,
        bytes: file.size,
        sha256: Digest::SHA256.file(file.to_s).hexdigest
      )
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def assemble
      tmp_artifact = @workdir.join("artifact.tar")
      run!([
        "tar", "-cf", tmp_artifact.to_s, "-C", @workdir.to_s,
        "manifest.json", DUMP_PATH, STORAGE_PATH
      ], timeout: TAR_TIMEOUT)

      final = Staging.artifact_path(@job_id)
      Staging.job_dir(@job_id).mkpath
      FileUtils.mv(tmp_artifact.to_s, final.to_s)

      info = {
        bytes: final.size,
        sha256: Digest::SHA256.file(final.to_s).hexdigest,
        created_at: Time.current.utc.iso8601
      }
      Staging.artifact_info_path(@job_id).write(JSON.generate(info))
      info
    end

    sig { params(argv: T::Array[String], timeout: Integer, env: T::Hash[String, String]).void }
    def run!(argv, timeout:, env: {})
      result = Shell.run(argv, timeout: timeout, env: env)
      return if result.success?

      raise Error, "#{argv.first} exited #{result.status}: #{result.stderr.presence || result.stdout}".truncate(500)
    end
  end
end
