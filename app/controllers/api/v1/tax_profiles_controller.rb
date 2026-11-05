# typed: true

module Api
  module V1
    # One editable tax profile per (household, tax_year), feeding the
    # exercise planner. GET returns a default (unpersisted) shape when the
    # year has no profile yet, so the UI always has something to render.
    class TaxProfilesController < BaseController
      # GET /api/v1/tax_profile?year=2026
      def show
        profile = TaxProfile.find_by(tax_year: year_param) ||
                  TaxProfile.new(tax_year: year_param, household: Current.household)
        render json: serialize(profile)
      end

      # PUT /api/v1/tax_profile — upsert by tax_year
      def update
        # HouseholdScoped#assign_household_from_current fills household_id on create.
        profile = TaxProfile.find_or_initialize_by(tax_year: params.require(:tax_year).to_i)
        profile.update!(profile_params)
        render json: serialize(profile)
      end

      private

      def profile_params
        params.permit(
          :filing_status, :state, :projected_state_tax, :projected_wages, :other_ordinary_income,
          :ltcg_qd_income, :itemizing, :salt_paid, :itemized_other,
          :prior_year_total_tax, :prior_year_agi,
          :ytd_withholding_federal, :ytd_withholding_state,
          :amt_credit_carryforward_federal, :amt_credit_carryforward_ca
        )
      end

      def serialize(profile)
        Api::Render::TaxProfile.new.profile(profile)
      end
    end
  end
end
