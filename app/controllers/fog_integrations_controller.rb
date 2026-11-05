# typed: strict
# frozen_string_literal: true

# The fog-integration/1 machine surface (fog:docs/integrations-contract.md):
# fog connects another app on the box to Fin through here, with a
# household admin's consent in between (FogIntegrations). Outside the
# console auth stack like FogController, authenticated by FOG_API_TOKEN.
class FogIntegrationsController < ActionController::API
  extend T::Sig

  include FogContractAuth

  before_action :authenticate_fog!

  # POST /fog/integrations {consumer, offer, return_to} — record the
  # request: 202 {id, consent}, the page on Fin's console a person answers
  # it on.
  sig { void }
  def create
    asked = FogIntegrations.ask(consumer: params[:consumer].to_s, offer: params[:offer].to_s,
      return_to: params[:return_to].presence&.to_s)
    render json: { id: asked.id, consent: asked.consent }, status: :accepted
  rescue FogIntegrations::Error => e
    render_fog_errors(e.message, status: :unprocessable_content)
  end

  # POST /fog/integrations/:id/claim — the secrets, once, after approval.
  # 409 while nobody has approved or once someone declined; 410 when it
  # expired or was claimed already.
  sig { void }
  def claim
    render json: { secrets: FogIntegrations.claim(params[:id].to_s) }
  rescue FogIntegrations::NotFound => e
    render_fog_errors(e.message, status: :not_found)
  rescue FogIntegrations::Waiting, FogIntegrations::Answered => e
    render_fog_errors(e.message, status: :conflict)
  rescue FogIntegrations::Gone => e
    render_fog_errors(e.message, status: :gone)
  end

  # GET /fog/integrations/:id
  sig { void }
  def show
    status = FogIntegrations.status(params[:id].to_s)
    render json: {
      id: status.id, active: status.active,
      created_at: status.created_at.iso8601, last_activity_at: status.last_activity_at&.iso8601
    }
  rescue FogIntegrations::NotFound => e
    render_fog_errors(e.message, status: :not_found)
  end

  # DELETE /fog/integrations/:id — revoke. 404 once it is gone, which fog
  # takes as already done.
  sig { void }
  def destroy
    FogIntegrations.disconnect(params[:id].to_s)
    head :no_content
  rescue FogIntegrations::NotFound => e
    render_fog_errors(e.message, status: :not_found)
  end
end
