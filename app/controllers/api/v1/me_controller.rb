# typed: true

module Api
  module V1
    class MeController < BaseController
      def show
        render json: Api::Render::Session.new.me(
          user: Current.user, household: Current.household, role: current_membership&.role
        )
      end
    end
  end
end
