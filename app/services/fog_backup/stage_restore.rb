# typed: strict
# frozen_string_literal: true

module FogBackup
  # Stages an artifact for restore-on-boot: the shared core of the setup
  # wizard's restore (POST /api/v1/setup/restore) and fog's machine surface
  # (POST /fog/restore). Moves an uploaded artifact into the staging path
  # (unless the caller says it was already placed there), preflights it, and
  # either arms restore-on-boot or — when the preflight refuses — disarms,
  # so a rejected artifact never sits staged where a later boot could
  # misread it as intentional.
  #
  # Callers keep their own guards (fresh instance, upload present) and
  # response shapes; the returned preflight says which way it went.
  module StageRestore
    extend T::Sig

    #
    # `rp_id` is the host the staging request arrived on. It stands in for
    # the RP ID on an instance that doesn't configure one, and rides in the
    # marker so restore-on-boot judges identity the same way this call did.
    sig do
      params(upload: T.untyped, staged: T::Boolean, confirm: T::Boolean, staged_by: String, rp_id: T.nilable(String))
        .returns(Preflight::Result)
    end
    def self.call(upload:, staged:, confirm:, staged_by:, rp_id: nil)
      Staging.restore_root.mkpath
      FileUtils.mv(upload.tempfile.path, Staging.pending_artifact.to_s) unless staged

      preflight = Preflight.check(artifact_path: Staging.pending_artifact, confirm_identity: confirm, rp_id: rp_id)
      if preflight.ok?
        Staging.arm!(confirm_identity: confirm, staged_by: staged_by, rp_id: rp_id)
      else
        Staging.disarm!
      end
      preflight
    end
  end
end
