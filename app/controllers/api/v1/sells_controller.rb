# typed: true

module Api
  module V1
    class SellsController < BaseController
      def index
        render_cached("sells", params: %i[from to limit offset]) do
          Api::Render::Sells.new(params: params).index
        end
      end
    end
  end
end
