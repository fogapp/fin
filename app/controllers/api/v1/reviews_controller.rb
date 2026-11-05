# typed: true

module Api
  module V1
    class ReviewsController < BaseController
      def show
        render_cached("review", params: %i[month]) { Api::Render::Review.new(params: params).show }
      end
    end
  end
end
