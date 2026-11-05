# typed: true

module Api
  module V1
    # Settings → Backup: produce a fog-backup/2 artifact on demand and take
    # it away. The same producer fog drives (FogBackup::Producer) does the
    # work, so what downloads here is byte-for-byte what a delegated backup
    # stores — it restores through fog's doors and through the first-run
    # restore on a fresh instance alike.
    #
    # A backup is instance-wide — every household's data, not only the
    # caller's — and any household admin may take one. That reading suits a
    # single-family instance; with FIN_OPEN_REGISTRATION left on, anyone
    # who registers founds a household they administer, so an instance open
    # to strangers should turn it off (INSTALL.md says so).
    class BackupsController < BaseController
      DOWNLOAD_TICKET_TTL = 5.minutes

      # The artifact is fetched by the browser's own download machinery,
      # which can't send the bearer header — it carries a short-lived signed
      # ticket minted by #download instead.
      skip_before_action :authenticate_with_token!, only: :artifact
      before_action -> { require_household_admin!("Only a household admin can manage backups.") }, except: :artifact

      # GET /api/v1/backups
      def index
        FogBackup::Staging.sweep_stale!
        render json: FogBackup::Serializer.overview_json(host: request.host)
      end

      # POST /api/v1/backups — start producing an artifact. 202 with the new
      # job; 200 with the running one when a manual backup is already under
      # way; 409 while fog is producing its own (it collects and deletes
      # that one, so there is nothing here to hand back).
      def create
        outcome = FogBackup::Trigger.call(
          origin: FogBackup::Staging::ORIGIN_MANUAL, requested_by: Current.user.email,
          host: request.host, rp_id: request.host
        )
        if !outcome.started && outcome.origin != FogBackup::Staging::ORIGIN_MANUAL
          return render json: { error: "A scheduled backup is being produced right now — try again in a minute." },
                        status: :conflict
        end

        if outcome.started
          Activity.record(source: "backup", event: "backup.requested",
                          summary: "#{Current.user.email} started a manual backup")
        end
        render json: FogBackup::Serializer.backup_json(outcome.job_id), status: outcome.started ? :accepted : :ok
      end

      # POST /api/v1/backups/:id/download — a ticketed URL for the artifact,
      # good for a few minutes.
      def download
        return render_not_found unless downloadable?(job_id)

        ticket = ticket_verifier.generate({ "job" => job_id }, expires_in: DOWNLOAD_TICKET_TTL)
        Activity.record(source: "backup", event: "backup.downloaded",
                        summary: "#{Current.user.email} downloaded a backup artifact")
        render json: {
          url:        "/api/v1/backups/#{job_id}/artifact?ticket=#{CGI.escape(ticket)}",
          expires_at: DOWNLOAD_TICKET_TTL.from_now
        }
      end

      # GET /api/v1/backups/:id/artifact?ticket=…
      def artifact
        payload = ticket_verifier.verified(params[:ticket].to_s)
        return render_unauthorized("Download link expired — start the download again") if payload.nil?
        return render_not_found unless payload["job"] == job_id && downloadable?(job_id)

        send_file FogBackup::Staging.artifact_path(job_id).to_s,
                  type: "application/x-tar", filename: FogBackup::Serializer.artifact_filename(job_id)
      end

      # DELETE /api/v1/backups/:id
      def destroy
        state = manual_job(job_id)
        return render_not_found if state.nil?
        if FogBackup::Staging.active_job_id == job_id
          return render json: { error: "This backup is still being produced." }, status: :conflict
        end

        FileUtils.rm_rf(FogBackup::Staging.job_dir(job_id))
        head :no_content
      end

      # POST /api/v1/backups/keys — the restore-critical secrets themselves.
      # An artifact's credential columns are encrypted with them and the
      # restore preflight refuses an instance that boots with different
      # ones, so moving to a new instance means carrying them across. POST,
      # never cached, and always on the activity log: this is the one place
      # the server's secrets leave it.
      def keys
        Activity.record(source: "backup", event: "backup.keys.revealed", severity: Severity::Warning,
                        summary: "#{Current.user.email} revealed the instance keys")
        response.headers["Cache-Control"] = "no-store"
        render json: {
          keys: FogBackup::Manifest.secret_values.map do |name, value|
            { name: name, value: value, fingerprint: FogBackup::Manifest.fingerprint(value) }
          end
        }
      end

      private

      def job_id
        params[:id].to_s.gsub(/[^0-9a-f]/, "")
      end

      # Fog's own jobs never surface here: fog collects and deletes them, and
      # a person deleting one mid-collection would fail a scheduled backup.
      def manual_job(id)
        state = FogBackup::Staging.status(id)
        state if state && FogBackup::Staging.job_origin(state) == FogBackup::Staging::ORIGIN_MANUAL
      end

      def downloadable?(id)
        state = manual_job(id)
        !state.nil? && state["status"] == "completed" && FogBackup::Staging.artifact_path(id).exist?
      end

      def ticket_verifier
        Rails.application.message_verifier(:backup_download)
      end
    end
  end
end
