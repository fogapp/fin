# typed: true

module Api
  module V1
    module Plaid
      class LinkTokensController < BaseController
        include PlaidErrorHandling

        def create
          response = PlaidClient.new.create_link_token(user_id: Current.user.id.to_s)
          render json: { link_token: response.link_token }, status: :created
        rescue => e
          render_plaid_error(e, fallback: "Failed to create Plaid link token")
        end
      end
    end
  end
end
