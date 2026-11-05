# typed: true

module Api
  module V1
    class AccountBalanceSnapshotsController < BaseController
      def index
        render json: Api::Render::AccountBalanceSnapshot.new(params: params).index
      end
    end
  end
end
