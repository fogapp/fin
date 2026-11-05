# typed: true

module Api
  module V1
    module Auth
      # Endpoints for managing a session AFTER initial auth. Right now this
      # only handles household-switching — minting a new token for a different
      # (user, household) pair so the active household reflected by the bearer
      # token can change without re-running the passkey ceremony.
      class SessionsController < BaseController
        # POST /api/v1/auth/switch_household
        # Body: { household_id }
        # Returns: { token, user, household } in the same shape as login.
        def switch_household
          target_id = params.require(:household_id)
          membership = Current.user.household_memberships.includes(:household).find_by(household_id: target_id)
          return render json: { error: "Not a member of that household." }, status: :forbidden unless membership

          household = membership.household
          token = ::Auth::SessionToken.successor!(from: Current.api_token, user: Current.user, household: household)

          render json: Api::Render::Session.new.serialize(
            user: Current.user, household: household, token: token, role: membership.role
          )
        end
      end
    end
  end
end
