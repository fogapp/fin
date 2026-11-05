# typed: true

module Api
  module V1
    module Equity
      class SummaryController < BaseController
        renders_with Api::Render::Equity

        def show
          # Per-grant vesting walk + value history — pure household read.
          render_cached("equity_summary") { renderer.summary }
        end
      end
    end
  end
end
