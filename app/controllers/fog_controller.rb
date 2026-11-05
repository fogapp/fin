# typed: strict
# frozen_string_literal: true

# The fog-backup machine surface (fog:docs/backup-contract.md): fog drives
# backups and restores through here. Deliberately outside the API token
# stack — the credential is FOG_API_TOKEN, a per-app shared secret fog
# injects at deploy, so the surface works on a fresh instance with zero
# users (which is exactly when a restore needs it). It also dodges the
# household default-scope: a backup is instance-wide, not household-scoped.
class FogController < ActionController::API
  extend T::Sig

  include FogContractAuth

  before_action :authenticate_fog!

  # GET /fog/backup — the descriptor: who this app is, what a backup of it
  # contains, whether the instance is fresh, and the last restore receipt.
  sig { void }
  def descriptor
    render json: FogBackup::Serializer.descriptor_json
  end

  # POST /fog/backup — start producing an artifact. 202 with the job to
  # poll; 409 with the running job when one is already producing.
  sig { void }
  def create_backup
    outcome = FogBackup::Trigger.call
    render json: { job: outcome.job_id }, status: outcome.started ? :accepted : :conflict
  end

  # GET /fog/backup/jobs/:id
  sig { void }
  def job_status
    payload = FogBackup::Serializer.job_json(job_id)
    return render_not_found if payload.nil?

    render json: payload
  end

  # GET /fog/backup/jobs/:id/artifact — the download fog verifies against
  # the job status' {bytes, sha256} claim.
  sig { void }
  def artifact
    state = FogBackup::Staging.status(job_id)
    path = FogBackup::Staging.artifact_path(job_id)
    return render_not_found unless state && state["status"] == "completed" && path.exist?

    send_file path.to_s, type: "application/x-tar",
      filename: "fin-#{Time.current.utc.strftime("%Y%m%d-%H%M%S")}.fogpack.tar"
  end

  # DELETE /fog/backup/jobs/:id — fog collected (and verified) the artifact;
  # drop the staged copy. Unless the job was started by a person from
  # Settings → Backup and fog merely adopted it (POST answered 409): that
  # artifact is still waiting for its download, and leaves with them or
  # with the 24 h sweep.
  sig { void }
  def destroy_job
    state = FogBackup::Staging.status(job_id)
    return render_not_found if state.nil?

    unless FogBackup::Staging.job_origin(state) == FogBackup::Staging::ORIGIN_MANUAL
      FileUtils.rm_rf(FogBackup::Staging.job_dir(job_id))
    end
    head :no_content
  end

  # POST /fog/restore — stage an artifact and arm restore-on-boot. Multipart
  # upload (field `artifact`), or staged:true when the file has already been
  # placed at the staging path by whoever holds the volume (fog does, for
  # restore-at-create). Fresh instances only: restoring over live data goes
  # through fog, which stops the app and stages directly.
  sig { void }
  def restore
    if User.exists?
      return render json: { errors: [ "This instance already has data — in-place restores go through fog, which stops the app first" ] },
        status: :conflict
    end

    staged = ActiveModel::Type::Boolean.new.cast(params[:staged])
    upload = params[:artifact]
    if !staged && !upload.respond_to?(:tempfile)
      return render json: { errors: [ "Provide an artifact upload or staged: true" ] }, status: :bad_request
    end

    preflight = FogBackup::StageRestore.call(
      upload: upload, staged: staged || false,
      confirm: ActiveModel::Type::Boolean.new.cast(params[:confirm_identity]) || false,
      staged_by: "fog-api"
    )
    return render json: { errors: preflight.errors }, status: :unprocessable_content unless preflight.ok?

    render json: { preflight: FogBackup::Serializer.preflight_json(preflight), restart_required: true }
  end

  private

  sig { returns(String) }
  def job_id
    params[:id].to_s.gsub(/[^0-9a-f]/, "")
  end

  sig { void }
  def render_not_found
    render json: { errors: [ "no such producer job" ] }, status: :not_found
  end
end
