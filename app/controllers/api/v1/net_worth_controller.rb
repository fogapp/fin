# typed: true

module Api
  module V1
    class NetWorthController < BaseController
      def index
        range = enum_param(NetWorthHistory::RangeKey, :range, default: NetWorthHistory::DEFAULT_RANGE)
        render_cached("net_worth", params: %i[range from to]) { Api::Render::NetWorth.new(params: params).index(range: T.must(range)) }
      end

      def projection
        render_cached("net_worth_projection", params: %i[years growth monthly]) do
          Api::Render::NetWorth.new(params: params).projection
        end
      end
    end
  end
end
