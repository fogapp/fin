# typed: strict
# frozen_string_literal: true

module Api
  module V1
    # First-run surface. Fin's account creation is passkey registration
    # (open while no users exist), so unlike hub/feed this controller only
    # answers two questions: "is this a fresh instance?" and "restore a
    # fog-backup artifact instead of starting fresh."
    class SetupController < ActionController::API
      extend T::Sig

      rate_limit to: 5, within: 10.minutes, only: :restore

      # Also how the console should sign people in: Fin's own passkeys, fog
      # alongside them, or fog alone (FogSignin). On fog the first sign-in
      # is the setup, so there is no first account to register.
      sig { void }
      def show
        FogSignin.attest_if_needed
        fog_only = FogSignin.fog_only?
        render json: {
          setup_required: !User.exists? && !fog_only,
          signin: { enabled: FogSignin.enabled?, fog_only: fog_only }
        }
      end

      # Stages + preflights the uploaded artifact, arms restore-on-boot, and
      # restarts the app; the entrypoint guard performs the restore before
      # serving again. Same once-only guard as open registration: after any
      # user exists this is a 403.
      sig { void }
      def restore
        return render json: { errors: [ "Setup already completed" ] }, status: :forbidden if User.exists?

        upload = params[:artifact]
        unless upload.respond_to?(:tempfile)
          return render json: { errors: [ "Provide a backup artifact file" ] }, status: :bad_request
        end

        preflight = FogBackup::StageRestore.call(
          upload: upload, staged: false,
          confirm: ActiveModel::Type::Boolean.new.cast(params[:confirm_identity]) || false,
          staged_by: "setup-wizard",
          # An instance that configures no RP ID binds passkeys to the host
          # it is reached on — this one. Without it a same-address restore
          # would read as a move, and a real move could not be named.
          rp_id: request.host
        )
        unless preflight.ok?
          return render json: { errors: preflight.errors, preflight: FogBackup::Serializer.preflight_json(preflight) },
            status: :unprocessable_content
        end

        FogBackup::Restart.schedule!
        render json: { restarting: true, preflight: FogBackup::Serializer.preflight_json(preflight) }
      end
    end
  end
end
