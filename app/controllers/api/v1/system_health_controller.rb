# typed: true

module Api
  module V1
    # Status panel for Settings › System; see Api::Render::SystemHealth.
    class SystemHealthController < BaseController
      def show
        render json: Api::Render::SystemHealth.new.show
      end
    end
  end
end
