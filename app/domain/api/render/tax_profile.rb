# typed: strict

module Api
  module Render
    # Serializes a TaxProfile for /api/v1/tax_profile and the exercise
    # planner. Numbers are floats; `complete` gates the planner endpoint.
    class TaxProfile < Api::Render::Base
      extend T::Sig

      sig { params(profile: ::TaxProfile).returns(T::Hash[Symbol, T.untyped]) }
      def profile(profile)
        {
          id:                              profile.id,
          persisted:                       profile.persisted?,
          tax_year:                        profile.tax_year,
          filing_status:                   profile.filing_status,
          state:                           profile.state,
          state_name:                      ::Tax::States.name_for(profile.state),
          state_tax_source:                profile.state_tax_source.serialize,
          projected_state_tax:             profile.projected_state_tax&.to_f,
          projected_wages:                 profile.projected_wages.to_f,
          other_ordinary_income:           profile.other_ordinary_income.to_f,
          ltcg_qd_income:                  profile.ltcg_qd_income.to_f,
          itemizing:                       profile.itemizing,
          salt_paid:                       profile.salt_paid.to_f,
          itemized_other:                  profile.itemized_other.to_f,
          prior_year_total_tax:            profile.prior_year_total_tax&.to_f,
          prior_year_agi:                  profile.prior_year_agi&.to_f,
          ytd_withholding_federal:         profile.ytd_withholding_federal.to_f,
          ytd_withholding_state:           profile.ytd_withholding_state.to_f,
          amt_credit_carryforward_federal: profile.amt_credit_carryforward_federal.to_f,
          amt_credit_carryforward_ca:      profile.amt_credit_carryforward_ca.to_f,
          complete:                        profile.complete?
        }
      end
    end
  end
end
