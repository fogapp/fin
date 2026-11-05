# typed: true

module Api
  module V1
    # The consent page's API (FogIntegrations): what fog is asking for an
    # app, and a household admin's answer. The ticket is the one in the
    # page's address, /connect/<ticket>, which fog sent the person to.
    class FogConnectionsController < BaseController
      extend T::Sig

      before_action :require_admin!

      rescue_from FogIntegrations::NotFound, with: :render_not_found
      rescue_from FogIntegrations::Answered, with: :render_answered
      rescue_from FogIntegrations::Gone, with: :render_gone

      # GET /api/v1/fog_connections/:ticket
      sig { void }
      def show
        render json: present(FogIntegrations.by_ticket(params[:ticket].to_s))
      end

      # POST /api/v1/fog_connections/:ticket/approve — mint the app's
      # read-only token in the caller's name; the browser then goes back to
      # fog with the answer.
      sig { void }
      def approve
        integration = FogIntegrations.approve!(params[:ticket].to_s, by: Current.user)
        render json: answered(integration, "approved")
      end

      # POST /api/v1/fog_connections/:ticket/decline
      sig { void }
      def decline
        integration = FogIntegrations.decline!(params[:ticket].to_s)
        render json: answered(integration, "declined")
      end

      private

      def require_admin!
        require_household_admin!("Only a household admin can let an app read Fin.")
      end

      sig { params(integration: FogIntegration).returns(T::Hash[Symbol, T.untyped]) }
      def present(integration)
        offer = FogIntegrations.offer_of(integration)
        {
          consumer:   integration.consumer,
          offer:      { id: offer.id, title: offer.title, blurb: offer.blurb },
          state:      integration.shown_state,
          expires_at: integration.expires_at.iso8601
        }
      end

      sig { params(integration: FogIntegration, result: String).returns(T::Hash[Symbol, String]) }
      def answered(integration, result)
        { state: integration.state.serialize, return_to: FogIntegrations.return_url(integration, result) }
      end

      def render_answered(exception)
        render json: { error: exception.message }, status: :conflict
      end

      def render_gone(exception)
        render json: { error: exception.message }, status: :gone
      end
    end
  end
end
