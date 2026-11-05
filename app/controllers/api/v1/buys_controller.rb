# typed: true

module Api
  module V1
    class BuysController < BaseController
      def index
        render_cached("buys", params: %i[from to limit offset]) do
          Api::Render::Buys.new(params: params).index
        end
      end
    end
  end
end
