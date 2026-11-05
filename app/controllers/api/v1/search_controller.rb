# typed: true

module Api
  module V1
    # Sitewide Cmd+K search; see Api::Render::Search.
    class SearchController < BaseController
      def index
        render json: Api::Render::Search.new(params: params).index
      end
    end
  end
end
