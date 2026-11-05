# typed: strict

module Api
  module Render
    # The exercise planner's payload for one option grant: crossover,
    # simulation, curve, scenarios, safe harbor, stress, and (NSO)
    # withholding gap under the household's tax profile. Everything is an
    # estimate under the profile's stated assumptions; see `exclusions`.
    class ExercisePlan < Api::Render::Base
      extend T::Sig

      EXCLUSIONS = T.let([
        "Net investment income tax (3.8%)",
        "Additional Medicare tax (0.9%)",
        "Multi-state allocation",
        "AMT foreign tax credit",
        "California itemized deductions",
        "AMT credit recovery (Form 8801 / FTB 3510) — coming in v2"
      ].freeze, T::Array[String])

      sig do
        params(
          grant: ::EquityGrant, profile: ::TaxProfile, planner: ::Equity::ExercisePlanner,
          tax_year: Integer, share_price: T.untyped, crossover: T.untyped,
          quantity: Float, drop_pct: Integer
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def plan(grant:, profile:, planner:, tax_year:, share_price:, crossover:, quantity:, drop_pct:)
        {
          tax_year:       tax_year,
          figures_status: {
            federal: ::Tax::Parameters.figures_status(:federal, tax_year),
            state:   ::Tax::Parameters.figures_status(:california, tax_year)
          },
          share_price:          share_price.to_f,
          strike_price:         grant.strike_price.to_f,
          exercisable_quantity: planner.exercisable_quantity,
          crossover:            crossover,
          simulation:           planner.simulate(quantity),
          curve:                planner.curve,
          scenarios:            planner.scenarios(quantity),
          safe_harbor:          planner.safe_harbor(quantity),
          stress:               planner.stress(quantity, drop_pct),
          nso_gap:              planner.nso_gap(quantity),
          escape_hatch_deadline: "#{tax_year}-12-31",
          exclusions:           EXCLUSIONS,
          profile:              Api::Render::TaxProfile.new.profile(profile)
        }
      end
    end
  end
end
