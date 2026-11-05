# typed: true

module Api
  module V1
    class PortfolioController < BaseController
      def index
        render_cached("portfolio") { Api::Render::Portfolio.new(params: params).index }
      end

      # TWR + XIRR over an explicit window (default: trailing year). The
      # window is capped at 10 years — PortfolioSeries walks every day.
      def performance
        from = params[:from].present? ? Date.iso8601(params[:from].to_s) : 1.year.ago.to_date
        to   = params[:to].present? ? Date.iso8601(params[:to].to_s) : Date.current
        from = [ from, 10.years.ago.to_date ].max

        render_cached("portfolio_performance", params: [ :from, :to ]) do
          Valuation::PortfolioPerformance.call(from: from, to: to)
        end
      end
    end
  end
end
