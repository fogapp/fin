# typed: true

module Api
  module V1
    module Equity
      # POST /api/v1/equity/grants/:id/exercise_plan — the exercise
      # planner's single read endpoint (see Api::Render::ExercisePlan).
      # This controller validates the grant and tax profile and resolves
      # the quantity; the renderer shapes the plan.
      class ExercisePlansController < BaseController
        def create
          grant = EquityGrant.find(params[:id])
          return render_plan_error("Exercise planning applies to option grants (ISO/NSO) only") unless grant.option?

          share_price = ::Equity::Valuation.current_share_price(T.must(grant.equity_company))
          return render_plan_error("no share value") if share_price.nil?

          tax_year = (params[:tax_year].presence || Date.current.year).to_i
          profile  = TaxProfile.find_by(tax_year: tax_year)
          if profile.nil? || !profile.complete?
            return render_plan_error("tax_profile_incomplete")
          end

          planner = ::Equity::ExercisePlanner.new(grant: grant, profile: profile, share_price: share_price)

          crossover = planner.crossover
          quantity  = resolve_quantity(planner, crossover)
          drop_pct  = (params[:stress_drop_pct].presence || ::Equity::ExercisePlanner::DEFAULT_STRESS_DROP).to_i

          render json: Api::Render::ExercisePlan.new.plan(
            grant: grant, profile: profile, planner: planner, tax_year: tax_year,
            share_price: share_price, crossover: crossover, quantity: quantity, drop_pct: drop_pct
          )
        rescue ::Tax::Parameters::Missing => e
          render_plan_error(e.message)
        end

        private

        def resolve_quantity(planner, crossover)
          raw = params[:quantity]
          quantity =
            if raw.present?
              raw.to_f
            elsif crossover
              crossover[:shares].to_f
            else
              planner.exercisable_quantity
            end
          quantity.clamp(0.0, planner.exercisable_quantity)
        end

        def render_plan_error(message)
          render json: { error: message }, status: :unprocessable_content
        end
      end
    end
  end
end
