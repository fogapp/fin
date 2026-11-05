# typed: true

module Api
  module V1
    class CashflowController < BaseController
      # The params Api::Render::Cashflow reads — the cache-key whitelist for
      # #index, #spend_breakdown and the get_cashflow MCP tool alike.
      CACHE_PARAMS = T.let(%i[from to account_id tag_id exclude_tag_ids category_id merchant_id].freeze, T::Array[Symbol])

      def index
        render_cached("cashflow", params: CACHE_PARAMS) { Api::Render::Cashflow.new(params: params).index }
      end

      def activity
        render json: Api::Render::CashflowActivity.new(params: params).index
      end

      def sankey
        # Validate up front (422 on an unknown value) — the renderer trusts it.
        enum_param(Api::Render::Cashflow::SankeyDimension, :dimension)
        render_cached("cashflow_sankey", params: CACHE_PARAMS + [ :dimension ]) do
          Api::Render::Cashflow.new(params: params).sankey
        end
      end

      # Split out of #index: only the Spending chart's stacked modes need it,
      # and #index is also what the dashboard widgets fetch.
      def spend_breakdown
        render_cached("cashflow_spend_breakdown", params: CACHE_PARAMS) do
          Api::Render::Cashflow.new(params: params).spend_breakdown
        end
      end
    end
  end
end
