# typed: true

module Api
  module V1
    class CostBasisController < BaseController
      def index
        # Position resolution + cost-basis math over the whole ledger — pure
        # household read, same caching contract as portfolio/net worth.
        render_cached("cost_basis") { Api::Render::CostBasis.new.index }
      end
    end
  end
end
