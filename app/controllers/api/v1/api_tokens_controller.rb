# typed: true

module Api
  module V1
    class ApiTokensController < BaseController
      renders_with Api::Render::ApiToken

      def index
        render json: renderer.index
      end

      def create
        token = Current.user.api_tokens.create!(
          name:       params[:name].presence,
          expires_at: params[:expires_at].presence,
          household:  Current.household
        )
        render json: renderer.serialize(token, include_token: true), status: :created
      end

      def destroy
        # Scope through Current.user so one member of a household can't
        # revoke another member's session tokens. HouseholdScoped already
        # filters by household; the user filter is the second key.
        Current.user.api_tokens.where(household_id: Current.household.id)
                               .find(params[:id]).destroy!
        head :no_content
      end
    end
  end
end
