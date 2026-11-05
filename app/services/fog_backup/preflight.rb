# typed: strict
# frozen_string_literal: true

require "rubygems/package"

module FogBackup
  # The gate in front of a restore (fog:docs/backup-contract.md): refuse
  # wrong-app, newer-schema, corrupt, or wrong-keys artifacts before touching
  # data; make identity drift — a different WebAuthn RP ID, which silently
  # invalidates every passkey — an explicit, confirmed decision.
  module Preflight
    extend T::Sig

    class Result < T::Struct
      extend T::Sig

      const :errors, T::Array[String]
      const :warnings, T::Array[String]
      const :manifest, T.nilable(Manifest::Parsed)

      sig { returns(T::Boolean) }
      def ok? = errors.empty?
    end

    # `rp_id` is the caller's fallback for this instance's RP ID (the host of
    # the request staging the restore) — see Manifest.current_rp_id.
    #
    # forget_secrets is the operator's decision, carried by fog's marker, that
    # the secrets the artifact was written with are gone for good: a mismatch
    # is then a warning, and the restore clears what they encrypted
    # (ForgetSecrets). Every other check refuses as before.
    sig do
      params(artifact_path: Pathname, confirm_identity: T::Boolean, rp_id: T.nilable(String),
        forget_secrets: T::Boolean).returns(Result)
    end
    def self.check(artifact_path:, confirm_identity: false, rp_id: nil, forget_secrets: false)
      errors = T.let([], T::Array[String])
      warnings = T.let([], T::Array[String])

      unless artifact_path.exist?
        return Result.new(errors: [ "No artifact staged at #{artifact_path}" ], warnings: [], manifest: nil)
      end

      digests = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
      manifest_json = T.let(nil, T.nilable(String))
      begin
        manifest_json, digests = scan_artifact(artifact_path)
      rescue StandardError => e
        return Result.new(errors: [ "Artifact is not readable as a tar: #{e.message}" ], warnings: [], manifest: nil)
      end
      if manifest_json.nil?
        return Result.new(errors: [ "Artifact has no manifest.json" ], warnings: [], manifest: nil)
      end

      manifest = begin
        Manifest.parse(manifest_json)
      rescue JSON::ParserError => e
        return Result.new(errors: [ "Manifest is not valid JSON: #{e.message}" ], warnings: [], manifest: nil)
      end

      unless Manifest::ACCEPTED_FORMATS.include?(manifest.format)
        errors << "Artifact declares format #{manifest.format.inspect}, expected one of #{Manifest::ACCEPTED_FORMATS.join(", ")}"
      end
      errors << "Artifact is for app #{manifest.app.inspect}, this is #{Manifest::APP}" unless Manifest.this_app?(manifest.app)

      check_schema_version(manifest, errors)
      check_components(manifest, digests, errors)
      check_file_components(manifest, errors)
      check_extensions(manifest, errors)
      check_secrets(manifest, forget_secrets ? warnings : errors, forget_secrets)
      check_identity(manifest, confirm_identity, Manifest.current_rp_id(fallback: rp_id), errors, warnings)

      Result.new(errors: errors, warnings: warnings, manifest: manifest)
    end

    # One pass over the tar: pull the manifest and hash every other entry, so
    # checksum verification never needs the artifact extracted.
    sig { params(artifact_path: Pathname).returns([ T.nilable(String), T::Hash[String, T::Hash[Symbol, T.untyped]] ]) }
    def self.scan_artifact(artifact_path)
      manifest_json = T.let(nil, T.nilable(String))
      digests = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
      artifact_path.open("rb") do |io|
        T.unsafe(Gem::Package::TarReader).new(io) do |tar|
          tar.each do |entry|
            name = entry.full_name.delete_prefix("./")
            if name == "manifest.json"
              manifest_json = entry.read.to_s
              next
            end
            digest = Digest::SHA256.new
            bytes = T.let(0, Integer)
            while (chunk = entry.read(1 << 16))
              digest << chunk
              bytes += chunk.bytesize
            end
            digests[name] = { sha256: digest.hexdigest, bytes: bytes }
          end
        end
      end
      [ manifest_json, digests ]
    end

    sig { params(manifest: Manifest::Parsed, errors: T::Array[String]).void }
    def self.check_schema_version(manifest, errors)
      code = Manifest.code_schema_version
      return if manifest.schema_version <= code

      errors << "Artifact schema #{manifest.schema_version} is newer than this code's #{code} — " \
        "update the app first, then restore (never restore forward)"
    end
    private_class_method :check_schema_version

    sig { params(manifest: Manifest::Parsed, digests: T::Hash[String, T::Hash[Symbol, T.untyped]], errors: T::Array[String]).void }
    def self.check_components(manifest, digests, errors)
      manifest.components.each do |component|
        path = component["path"].to_s
        actual = digests[path]
        if actual.nil?
          errors << "Component #{path} is listed in the manifest but missing from the artifact"
          next
        end
        if actual[:sha256] != component["sha256"].to_s
          errors << "Component #{path} fails checksum verification — the artifact is corrupt"
        elsif actual[:bytes] != component["bytes"].to_i
          errors << "Component #{path} is #{actual[:bytes]} bytes, manifest says #{component["bytes"]}"
        end
      end
    end
    private_class_method :check_components

    # File components are unpacked by their extension — fog-backup/1 wrote
    # `.tar.zst`, fog-backup/2 a plain `.tar` — into the tree their name
    # stands for. Fin has one, `storage`. Anything else is refused here
    # rather than met halfway through a restore, after the database has
    # already been replaced.
    sig { params(manifest: Manifest::Parsed, errors: T::Array[String]).void }
    def self.check_file_components(manifest, errors)
      manifest.file_components.each do |component|
        name = component["name"].to_s
        path = component["path"].to_s
        if FILE_TREES.exclude?(name)
          errors << "File component #{name.inspect} is not one this app restores"
        elsif archive_codec(path).nil?
          errors << "File component #{path} is neither a .tar nor a .tar.zst"
        end
      end
    end
    private_class_method :check_file_components

    # The file components Fin restores, by name.
    FILE_TREES = T.let(%w[storage].freeze, T::Array[String])

    # How a file component's archive is unpacked, read from its extension:
    # :zstd for `.tar.zst`, :plain for `.tar`, nil for anything else.
    sig { params(path: String).returns(T.nilable(Symbol)) }
    def self.archive_codec(path)
      if path.end_with?(".tar.zst") then :zstd
      elsif path.end_with?(".tar") then :plain
      end
    end

    sig { params(manifest: Manifest::Parsed, errors: T::Array[String]).void }
    def self.check_extensions(manifest, errors)
      installed = Manifest.installed_extensions
      manifest.extensions.each do |name, wanted|
        current = installed[name]
        if current.nil?
          errors << "Postgres extension #{name} (#{wanted}) is required by the artifact but not installed"
          next
        end
        begin
          if Gem::Version.new(current) < Gem::Version.new(wanted)
            errors << "Postgres extension #{name} is #{current}, artifact needs #{wanted} or newer"
          end
        rescue ArgumentError
          nil # unparseable extension version strings — presence is enough
        end
      end
    end
    private_class_method :check_extensions

    sig { params(manifest: Manifest::Parsed, findings: T::Array[String], forgetting: T::Boolean).void }
    def self.check_secrets(manifest, findings, forgetting)
      current = Manifest.secrets_fingerprint
      manifest.secrets_fingerprint.each do |key, fingerprint|
        if current[key].nil?
          findings << if forgetting
            "#{key} is not set on this instance (restoring without it: what it encrypted is cleared)"
          else
            "#{key} is not set on this instance but the artifact's data was written with it — " \
              "restoring would produce unreadable ciphertext"
          end
        elsif current[key] != fingerprint
          findings << if forgetting
            "#{key} differs from the one the artifact was written with (restoring without it: what it encrypted is cleared)"
          else
            "#{key} differs from the one the artifact was written with — " \
              "restoring would produce unreadable ciphertext; inject the original value first"
          end
        end
      end
    end
    private_class_method :check_secrets

    # A passkey is bound to its RP ID: restore under a different one and no
    # existing passkey signs in. Proceeding must be a decision, never a
    # default — the way back in is a sign-in link issued for the new address
    # (Auth::DeviceInvite), which the messages name.
    sig do
      params(manifest: Manifest::Parsed, confirm_identity: T::Boolean, current_rp: T.nilable(String),
        errors: T::Array[String], warnings: T::Array[String]).void
    end
    def self.check_identity(manifest, confirm_identity, current_rp, errors, warnings)
      artifact_rp = manifest.identity_rp_id
      return if artifact_rp.nil? || artifact_rp == current_rp

      message = "Artifact's passkeys are bound to RP ID #{artifact_rp.inspect}, this instance declares #{current_rp.inspect} — " \
        "every existing passkey stops working under a different RP ID"
      if confirm_identity
        warnings << "#{message} (confirmed, proceeding — sign in with a sign-in link issued for this address)"
      else
        errors << "#{message}; set FIN_WEBAUTHN_RP_ID to match, or pass confirm_identity to proceed anyway " \
          "and sign in with a sign-in link issued for this address"
      end
    end
    private_class_method :check_identity
  end
end
