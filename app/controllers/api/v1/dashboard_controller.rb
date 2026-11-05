# typed: true

module Api
  module V1
    class DashboardController < BaseController
      def index
        render_cached("dashboard", params: %i[broker_id from]) { Api::Render::Dashboard.new(params: params).index }
      end
    end
  end
end
