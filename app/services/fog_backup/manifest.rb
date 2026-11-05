# typed: strict
# frozen_string_literal: true

module FogBackup
  # The artifact's self-description (fog:docs/backup-contract.md). Built by
  # the producer, parsed by preflight; fog stores it verbatim beside the
  # artifact. Plaintext by design — a backup you can't identify without keys
  # is a backup you can't manage.
  module Manifest
    extend T::Sig

    # The format this app writes. fog-backup/2 is fog-backup/1 with its
    # payloads uncompressed (`pg_dump -Fc -Z0`, plain file tars): fog's store
    # deduplicates chunks and compresses them itself, and a payload
    # compressed as a whole shares nothing with the night before.
    FORMAT = T.let("fog-backup/2", String)
    # Every format a restore accepts, so any backup this app ever made
    # still restores.
    ACCEPTED_FORMATS = T.let(%w[fog-backup/1 fog-backup/2].freeze, T::Array[String])
    APP = T.let("fin", String)
    # Names this app's artifacts carried before. Fin was Manor until
    # 2026-11, and its backups move into a Fin install, so preflight takes
    # them as this app's own.
    LEGACY_APPS = T.let(%w[manor].freeze, T::Array[String])

    sig { params(app: String).returns(T::Boolean) }
    def self.this_app?(app) = app == APP || LEGACY_APPS.include?(app)

    # The env values whose loss bricks a restore. Only their fingerprints
    # travel. Fin's ten encrypted credential columns (Plaid, Alchemy,
    # Coinbase, Tiingo…) hang off the AR_ENCRYPTION_* triple, and
    # SECRET_KEY_BASE is the HMAC behind every passkey user handle.
    FINGERPRINTED_SECRETS = T.let(%w[
      AR_ENCRYPTION_PRIMARY_KEY
      AR_ENCRYPTION_DETERMINISTIC_KEY
      AR_ENCRYPTION_KEY_DERIVATION_SALT
      SECRET_KEY_BASE
    ].freeze, T::Array[String])

    class Component < T::Struct
      const :name, String
      const :path, String
      const :kind, String
      const :bytes, Integer
      const :sha256, String
    end

    sig do
      params(components: T::Array[Component], host: T.nilable(String), rp_id: T.nilable(String))
        .returns(T::Hash[Symbol, T.untyped])
    end
    def self.build(components:, host: nil, rp_id: nil)
      {
        format: FORMAT,
        app: APP,
        created_at: Time.current.utc.iso8601,
        produced_by: { git_sha: ENV["GIT_SHA"].presence || "unknown",
                       schema_version: code_schema_version.to_s },
        pg: pg_info,
        components: components.map { |c| { name: c.name, path: c.path, kind: c.kind, bytes: c.bytes, sha256: c.sha256 } },
        external: [],
        # Fin is single-database: the dump includes solid_queue/solid_cache
        # tables, which restore truncates (stale claimed jobs are wreckage).
        excluded: %w[queue_state cache_state],
        identity: identity(host: host, rp_id: rp_id),
        secrets_fingerprint: secrets_fingerprint
      }
    end

    # Where this instance's data is bound. A passkey is tied to its RP ID;
    # restoring under a different one invalidates every credential, so the
    # RP ID is recorded for preflight to make that a decision, not a surprise.
    #
    # The configured FIN_WEBAUTHN_RP_ID wins. Instances that configure
    # nothing derive the RP ID from each request's host (WebauthnRelyingParty),
    # so a backup requested from the browser passes that host in — without it
    # the artifact would claim no identity at all and a move to another
    # address would restore silently into a lock-out.
    #
    # `host` is the same fact in the form fog reads: fog's restore doors ask
    # the operator to confirm an artifact that names a host, and hand that
    # confirmation to restore-on-boot. With no host, fog arms the restore
    # unconfirmed and the app's own preflight refuses it at boot.
    sig { params(host: T.nilable(String), rp_id: T.nilable(String)).returns(T::Hash[Symbol, T.nilable(String)]) }
    def self.identity(host: nil, rp_id: nil)
      effective_rp = current_rp_id(fallback: rp_id)
      { host: host.presence || effective_rp, webauthn_rp_id: effective_rp }
    end

    # The RP ID this instance's passkeys are bound to, as far as it can be
    # known without a request: the configured one, else the caller's fallback
    # (the host of the request that asked).
    sig { params(fallback: T.nilable(String)).returns(T.nilable(String)) }
    def self.current_rp_id(fallback: nil)
      ENV["FIN_WEBAUTHN_RP_ID"].presence || fallback.presence
    end

    # The restore-critical env values themselves, for the one place that
    # hands them to a person (Settings → Backup): a second instance can only
    # read this one's encrypted columns if it boots with the same values.
    sig { returns(T::Hash[String, String]) }
    def self.secret_values
      FINGERPRINTED_SECRETS.each_with_object({}) do |key, out|
        value = ENV[key].presence
        out[key] = value unless value.nil?
      end
    end

    sig { params(value: String).returns(String) }
    def self.fingerprint(value) = "sha256:#{Digest::SHA256.hexdigest(value).first(12)}"

    # The code's newest migration, read from db/migrate rather than the
    # database — preflight runs against a database that may not have a schema
    # yet (restore-at-create lands before db:prepare).
    sig { returns(Integer) }
    def self.code_schema_version
      paths = ActiveRecord::Migrator.migrations_paths
      ActiveRecord::MigrationContext.new(paths).migrations.map(&:version).max || 0
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def self.pg_info
      connection = ActiveRecord::Base.connection
      server_num = connection.select_value("SELECT current_setting('server_version_num')").to_i
      {
        server_major: server_num / 10_000,
        dump_tool: dump_tool_version,
        extensions: installed_extensions
      }
    end

    # The client tooling that produced the dump (the contract's `pg.dump_tool`).
    # Fog's pg-dump-skew check reads it from the newest manifest whenever it
    # cannot probe a running container — a stopped app otherwise keeps a
    # stale finding forever. Nil when pg_dump is missing; the producer fails
    # loudly on that in its own right.
    sig { returns(T.nilable(String)) }
    def self.dump_tool_version
      result = Shell.run([ "pg_dump", "--version" ], timeout: 10)
      return nil unless result.success?

      result.stdout.lines.first&.strip.presence
    rescue StandardError
      nil
    end

    sig { returns(T::Hash[String, String]) }
    def self.installed_extensions
      rows = ActiveRecord::Base.connection.select_rows(
        "SELECT extname, extversion FROM pg_extension WHERE extname <> 'plpgsql'"
      )
      rows.to_h { |name, version| [ name.to_s, version.to_s ] }
    end

    sig { returns(T::Hash[String, String]) }
    def self.secrets_fingerprint
      secret_values.transform_values { |value| fingerprint(value) }
    end

    # ---- parsing (preflight side) ----

    class Parsed < T::Struct
      extend T::Sig

      const :raw, T::Hash[String, T.untyped]

      sig { returns(String) }
      def format = raw["format"].to_s

      sig { returns(String) }
      def app = raw["app"].to_s

      sig { returns(T.nilable(String)) }
      def created_at = raw["created_at"]&.to_s

      sig { returns(Integer) }
      def schema_version = raw.dig("produced_by", "schema_version").to_i

      sig { returns(T.nilable(String)) }
      def git_sha = raw.dig("produced_by", "git_sha")&.to_s

      # The client that produced the dump, as the contract's `pg.dump_tool`.

      sig { returns(T.nilable(String)) }
      def dump_tool = (raw["pg"] || {})["dump_tool"]&.to_s.presence


      sig { returns(T::Hash[String, String]) }
      def extensions
        (raw.dig("pg", "extensions") || {}).to_h { |k, v| [ k.to_s, v.to_s ] }
      end

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def components = Array(raw["components"])

      # The db component's entry (fog-backup/1 and /2 both name it
      # "primary" at db/primary.dump, but the entry is what says so).
      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def primary = components.find { |c| c["kind"] == "db" && c["name"] == "primary" }

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def file_components = components.select { |c| c["kind"] == "files" }

      sig { returns(T::Hash[String, String]) }
      def secrets_fingerprint
        (raw["secrets_fingerprint"] || {}).to_h { |k, v| [ k.to_s, v.to_s ] }
      end

      sig { returns(T.nilable(String)) }
      def identity_rp_id = raw.dig("identity", "webauthn_rp_id")&.to_s.presence
    end

    sig { params(json: String).returns(Parsed) }
    def self.parse(json)
      Parsed.new(raw: JSON.parse(json))
    end
  end
end
