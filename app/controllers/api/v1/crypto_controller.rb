# typed: true

module Api
  module V1
    class CryptoController < BaseController
      def index
        render_cached("crypto", params: %i[from to limit offset]) do
          Api::Render::Crypto.new(params: params).index
        end
      end
    end
  end
end
