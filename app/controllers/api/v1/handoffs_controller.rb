# typed: strict
# frozen_string_literal: true

module Api
  module V1
    # The console's half of a fog sign-in: the callback put a one-time code
    # in the URL fragment; this exchanges it for the session's token, the
    # same shape a passkey sign-in answers with. The console-minted recovery
    # link (bin/rails fin:recovery_link) arrives the same way.
    class HandoffsController < ActionController::API
      extend T::Sig

      rate_limit to: 20, within: 1.minute, only: :create

      # POST /api/v1/handoff  { handoff }
      sig { void }
      def create
        token = ApiToken.redeem_handoff(params.require(:handoff).to_s)
        if token.nil?
          return render json: { error: "This sign-in link has expired; sign in again." }, status: :unauthorized
        end

        user = T.must(token.user)
        household = T.must(token.household)
        role = user.household_memberships.find_by(household_id: household.id)&.role
        render json: Api::Render::Session.new.serialize(user: user, household: household, token: token, role: role),
          status: :created
      rescue ActionController::ParameterMissing
        render json: { error: "handoff is required" }, status: :bad_request
      end
    end
  end
end
