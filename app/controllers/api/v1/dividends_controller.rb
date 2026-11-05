# typed: true

module Api
  module V1
    class DividendsController < BaseController
      def index
        render_cached("dividends", params: %i[from to limit offset]) do
          Api::Render::Dividends.new(params: params).index
        end
      end
    end
  end
end
