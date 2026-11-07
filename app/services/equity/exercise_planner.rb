# typed: strict

module Equity
  # The integration layer between the equity model and the tax engines
  # (docs/exercise-planner-design.md): given an option grant and the
  # household's tax profile, computes the $0-AMT crossover, per-quantity
  # simulations, the tax-owed curve, hold/sale scenarios, safe-harbor
  # status, the post-Dec-31 downside stress, and (for NSOs) the
  # under-withholding gap.
  #
  # All outputs are estimates under the profile's stated assumptions —
  # incremental AMT always means amt(spread) − amt(0); a profile can already
  # be in AMT before exercising a single share.
  class ExercisePlanner
    extend T::Sig

    BISECTION_ITERATIONS = 60
    BISECTION_TOLERANCE  = 1.0 # dollars
    CURVE_POINTS         = 41
    DEFAULT_STRESS_DROP  = 60

    FEDERAL_SUPPLEMENTAL_WITHHOLDING = 0.22

    sig { params(grant: EquityGrant, profile: TaxProfile, share_price: BigDecimal).void }
    def initialize(grant:, profile:, share_price:)
      @grant       = grant
      @profile     = profile
      @share_price = share_price
      @tax_year    = T.let(profile.tax_year, Integer)
      @pairs       = T.let({}, T::Hash[T.untyped, Tax::JurisdictionPair])
    end

    sig { returns(T::Boolean) }
    def iso?
      @grant.grant_type == EquityGrant::GrantType::Iso
    end

    sig { returns(Float) }
    def exercisable_quantity
      [ @grant.vested_quantity - @grant.exercised_quantity, BigDecimal("0") ].max.to_f
    end

    sig { returns(Float) }
    def spread_per_share
      [ @share_price - @grant.strike_price.to_d, BigDecimal("0") ].max.to_f
    end

    # ------------------------------------------------------------- crossover

    # Max whole shares exercisable this year with $0 incremental AMT.
    # Federal and CA crossovers are found separately by bisection over the
    # forward engines (robust to phaseout kinks and LTCG stacking); the
    # binding jurisdiction is whichever runs out first. ISO only.
    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def crossover
      return nil unless iso?

      max_spread = exercisable_quantity * spread_per_share
      federal_max    = max_zero_amt_spread(:federal, max_spread)
      california_max = max_zero_amt_spread(:california, max_spread)

      binding_spread = [ federal_max, california_max ].min
      shares = spread_per_share.positive? ? (binding_spread / spread_per_share).floor : 0

      {
        shares:  shares,
        spread:  (shares * spread_per_share).round(2),
        binding: federal_max <= california_max ? "federal" : "california"
      }
    end

    # -------------------------------------------------------------- simulate

    sig { params(quantity: Float).returns(T::Hash[Symbol, T.untyped]) }
    def simulate(quantity)
      spread     = quantity * spread_per_share
      federal    = incremental_federal_amt(spread)
      california = incremental_california_amt(spread)
      cost       = @grant.strike_price.to_d.to_f * quantity

      {
        quantity:                quantity,
        spread:                  spread.round(2),
        federal_amt:             federal.round(2),
        california_amt:          california.round(2),
        exercise_cost:           cost.round(2),
        total_cash_needed:       (cost + federal + california).round(2),
        marginal_rate_next_share: marginal_rate_next_share(spread),
        post_exercise_agi:       baseline_agi.round(2), # ISO hold leaves AGI unchanged
        post_exercise_federal_amti: federal_result(spread)[:amti]
      }
    end

    # ----------------------------------------------------------------- curve

    # 41 evenly spaced quantities from 0 to exercisable, each with its
    # incremental AMT split. Monotone non-decreasing in total.
    sig { returns(T::Array[T::Hash[Symbol, Float]]) }
    def curve
      max = exercisable_quantity
      step = max / (CURVE_POINTS - 1)

      (0...CURVE_POINTS).map do |i|
        quantity = (i == CURVE_POINTS - 1) ? max : i * step
        spread = quantity * spread_per_share
        federal    = incremental_federal_amt(spread)
        california = incremental_california_amt(spread)
        {
          quantity:       quantity.round(4),
          federal_amt:    federal.round(2),
          california_amt: california.round(2),
          total:          (federal + california).round(2)
        }
      end
    end

    # ------------------------------------------------------------- scenarios

    sig { params(quantity: Float).returns(T::Hash[Symbol, T.untyped]) }
    def scenarios(quantity)
      iso? ? iso_scenarios(quantity) : nso_scenarios(quantity)
    end

    # ----------------------------------------------------------- safe harbor

    sig { params(quantity: Float).returns(T::Hash[Symbol, T.untyped]) }
    def safe_harbor(quantity)
      spread = quantity * spread_per_share
      {
        federal:    federal_safe_harbor(spread),
        california: california_safe_harbor(spread)
      }
    end

    # ---------------------------------------------------------------- stress

    sig { params(quantity: Float, drop_pct: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def stress(quantity, drop_pct)
      spread      = quantity * spread_per_share
      price_after = @share_price.to_f * (1 - drop_pct / 100.0)
      value_after = quantity * price_after
      # AMT is locked to the FMV at exercise — a later price drop changes
      # nothing about the exercise-year bill.
      tax = incremental_federal_amt(spread) + incremental_california_amt(spread)
      cost = @grant.strike_price.to_d.to_f * quantity

      {
        drop_pct:          drop_pct,
        price_after:       price_after.round(4),
        share_value_after: value_after.round(2),
        tax_still_owed:    tax.round(2),
        underwater:        (tax + cost - value_after).round(2)
      }
    end

    # --------------------------------------------------------------- nso gap

    # Estimated under-withholding on an NSO exercise: statutory supplemental
    # rates (22% federal, 10.23% CA) vs the profile's actual marginal
    # ordinary rates. Floored at zero per jurisdiction.
    sig { params(quantity: Float).returns(T.nilable(T::Hash[Symbol, Float])) }
    def nso_gap(quantity)
      return nil if iso?

      spread = quantity * spread_per_share
      federal_marginal = federal_marginal_ordinary_rate
      ca_marginal      = california_marginal_ordinary_rate
      ca_supplemental  = Tax::Parameters.california(@tax_year).fetch(:supplemental_withholding_rate)

      federal_gap = [ spread * (federal_marginal - FEDERAL_SUPPLEMENTAL_WITHHOLDING), 0.0 ].max
      ca_gap      = [ spread * (ca_marginal - ca_supplemental), 0.0 ].max

      {
        spread:                    spread.round(2),
        federal_marginal_rate:     federal_marginal.round(4),
        federal_withholding_rate:  FEDERAL_SUPPLEMENTAL_WITHHOLDING,
        federal_gap:               federal_gap.round(2),
        california_marginal_rate:  ca_marginal.round(4),
        california_withholding_rate: ca_supplemental,
        california_gap:            ca_gap.round(2),
        total_gap:                 (federal_gap + ca_gap).round(2)
      }
    end

    private

    # ----------------------------------------------------------- tax engines

    # One memoized Tax::JurisdictionPair per (spread, extras) input set; the
    # pair memoizes each engine run internally, replacing the old per-result
    # @amt_cache while keeping every construction path identical.
    sig { params(spread: Float, other_ordinary_extra: Float, ltcg_extra: Float).returns(Tax::JurisdictionPair) }
    def pair_for(spread, other_ordinary_extra: 0.0, ltcg_extra: 0.0)
      key = [ spread.round(2), other_ordinary_extra.round(2), ltcg_extra.round(2) ]
      @pairs[key] ||= Tax::JurisdictionPair.new(
        tax_year:       @tax_year,
        filing_status:  @profile.filing_status,
        wages:          @profile.projected_wages,
        other_ordinary: @profile.other_ordinary_income.to_d + BigDecimal(other_ordinary_extra.to_s),
        ltcg_qd:        @profile.ltcg_qd_income.to_d + BigDecimal(ltcg_extra.to_s),
        itemizing:      @profile.itemizing,
        salt_paid:      @profile.salt_paid,
        itemized_other: @profile.itemized_other,
        iso_spread:     spread
      )
    end

    sig { params(spread: Float, other_ordinary_extra: Float, ltcg_extra: Float).returns(T::Hash[Symbol, Float]) }
    def federal_result(spread, other_ordinary_extra: 0.0, ltcg_extra: 0.0)
      pair_for(spread, other_ordinary_extra: other_ordinary_extra, ltcg_extra: ltcg_extra).federal
    end

    sig { params(spread: Float, other_ordinary_extra: Float, ltcg_extra: Float).returns(T::Hash[Symbol, Float]) }
    def california_result(spread, other_ordinary_extra: 0.0, ltcg_extra: 0.0)
      pair_for(spread, other_ordinary_extra: other_ordinary_extra, ltcg_extra: ltcg_extra).california
    end

    sig { params(spread: Float).returns(Float) }
    def incremental_federal_amt(spread)
      federal_result(spread).fetch(:amt) - federal_result(0.0).fetch(:amt)
    end

    sig { params(spread: Float).returns(Float) }
    def incremental_california_amt(spread)
      california_result(spread).fetch(:amt) - california_result(0.0).fetch(:amt)
    end

    sig { params(spread: Float).returns(Float) }
    def total_incremental_amt(spread)
      incremental_federal_amt(spread) + incremental_california_amt(spread)
    end

    # ------------------------------------------------------------- crossover

    # Bisection for the largest spread with (approximately) zero incremental
    # AMT in one jurisdiction. Incremental AMT is monotone non-decreasing in
    # spread, so the predicate is monotone and bisection is exact to the
    # tolerance.
    sig { params(jurisdiction: Symbol, max_spread: Float).returns(Float) }
    def max_zero_amt_spread(jurisdiction, max_spread)
      incremental = ->(spread) do
        jurisdiction == :federal ? incremental_federal_amt(spread) : incremental_california_amt(spread)
      end

      return 0.0 if max_spread <= 0

      # Already in AMT at spread 0: TMT rises with every additional dollar
      # of spread while regular tax stays put, so incremental AMT is
      # positive for any spread — crossover is exactly zero.
      base_amt = jurisdiction == :federal ? federal_result(0.0).fetch(:amt) : california_result(0.0).fetch(:amt)
      return 0.0 if base_amt.positive?

      return max_spread if incremental.call(max_spread) <= BISECTION_TOLERANCE

      lo = 0.0
      hi = max_spread
      BISECTION_ITERATIONS.times do
        break if (hi - lo) <= BISECTION_TOLERANCE

        mid = (lo + hi) / 2.0
        if incremental.call(mid) <= BISECTION_TOLERANCE
          lo = mid
        else
          hi = mid
        end
      end
      lo
    end

    # --------------------------------------------------------------- helpers

    sig { returns(Float) }
    def baseline_agi
      (@profile.projected_wages.to_d + @profile.other_ordinary_income.to_d +
        @profile.ltcg_qd_income.to_d).to_f
    end

    sig { params(spread: Float).returns(Float) }
    def marginal_rate_next_share(spread)
      per_share = spread_per_share
      return 0.0 unless per_share.positive?

      ((total_incremental_amt(spread + per_share) - total_incremental_amt(spread)) / per_share).round(4).to_f
    end

    # Marginal ordinary rates at zero additional spread — the bracket math
    # (including the CA BHST surcharge) lives on the shared pair.
    sig { returns(Float) }
    def federal_marginal_ordinary_rate
      pair_for(0.0).federal_marginal_ordinary_rate
    end

    sig { returns(Float) }
    def california_marginal_ordinary_rate
      pair_for(0.0).california_marginal_ordinary_rate
    end

    # ------------------------------------------------------------- scenarios

    sig { params(quantity: Float).returns(T::Hash[Symbol, T.untyped]) }
    def iso_scenarios(quantity)
      spread   = quantity * spread_per_share
      proceeds = @share_price.to_f * quantity
      gain     = spread # (price − strike) × qty at the current price

      {
        hold: {
          federal:    incremental_federal_amt(spread).round(2),
          california: incremental_california_amt(spread).round(2),
          note:       "AMT is largely recoverable as a credit in the sale year (not yet modeled)"
        },
        same_year_sale: {
          # Disqualifying disposition in the exercise year: the spread is
          # ordinary income and the AMT adjustment disappears entirely.
          federal:    (liability(federal_result(0.0, other_ordinary_extra: spread)) -
                       liability(federal_result(0.0))).round(2),
          california: (liability(california_result(0.0, other_ordinary_extra: spread)) -
                       liability(california_result(0.0))).round(2),
          proceeds:   proceeds.round(2),
          note:       "Disqualifying disposition: spread taxed as ordinary income, no AMT"
        },
        qualifying_sale: {
          exercise_year: {
            federal:    incremental_federal_amt(spread).round(2),
            california: incremental_california_amt(spread).round(2)
          },
          sale_year: {
            # Sale at the current price in a future year, same profile:
            # federal LTCG stacked on baseline income; CA taxes the full
            # gain as ordinary income.
            federal:    (liability(federal_result(0.0, ltcg_extra: gain)) -
                         liability(federal_result(0.0))).round(2),
            california: (liability(california_result(0.0, ltcg_extra: gain)) -
                         liability(california_result(0.0))).round(2)
          },
          note: "Exercise-year AMT is largely recovered via the Form 8801 / FTB 3510 credit in the sale year (not yet modeled)"
        }
      }
    end

    sig { params(quantity: Float).returns(T::Hash[Symbol, T.untyped]) }
    def nso_scenarios(quantity)
      spread = quantity * spread_per_share

      {
        exercise: {
          # NSO spread is ordinary income at exercise, federal + CA.
          federal:    (liability(federal_result(0.0, other_ordinary_extra: spread)) -
                       liability(federal_result(0.0))).round(2),
          california: (liability(california_result(0.0, other_ordinary_extra: spread)) -
                       liability(california_result(0.0))).round(2),
          nso_gap:    nso_gap(quantity),
          note:       "NSO spread is ordinary income at exercise; withholding at statutory supplemental rates usually undershoots the real liability"
        }
      }
    end

    # Total liability for scenario deltas: max(regular, TMT) — equivalently
    # regular + AMT.
    sig { params(result: T::Hash[Symbol, Float]).returns(Float) }
    def liability(result)
      result.fetch(:regular_tax) + result.fetch(:amt)
    end

    # ----------------------------------------------------------- safe harbor

    # Both harbors delegate the shared required/covered math (and the CA $1M
    # AGI ceiling) to Tax::SafeHarbor; the planner layers on the
    # exercise-specific pieces — the AMT set-aside and the guidance notes.

    sig { params(spread: Float).returns(T::Hash[Symbol, T.untyped]) }
    def federal_safe_harbor(spread)
      base = Tax::SafeHarbor.federal(profile: @profile, tax_year: @tax_year,
                                     paid: @profile.ytd_withholding_federal.to_d.to_f)
      return base if base[:status] == "unknown"

      covered = base[:status] == "covered"
      base.merge(
        withheld:  @profile.ytd_withholding_federal.to_f,
        set_aside: covered ? incremental_federal_amt(spread).round(2) : nil,
        note: covered ?
          "Withholding meets the prior-year safe harbor (withholding is deemed evenly paid) — the AMT bill is due April 15; set the cash aside" :
          "Withholding is below the prior-year safe harbor — estimated payments may be needed to avoid an underpayment penalty"
      )
    end

    sig { params(spread: Float).returns(T::Hash[Symbol, T.untyped]) }
    def california_safe_harbor(spread)
      # An ISO exercise-and-hold adds to AMTI but NOT to AGI, so it cannot
      # by itself trip the $1M rule. NSO spread is ordinary income and does.
      current_agi = baseline_agi
      current_agi += spread unless iso?

      base = Tax::SafeHarbor.california(profile: @profile, tax_year: @tax_year,
                                        paid: @profile.ytd_withholding_state.to_d.to_f,
                                        current_agi: current_agi)
      return base unless %w[covered uncovered].include?(base[:status])

      covered = base[:status] == "covered"
      incremental = iso? ? incremental_california_amt(spread) : 0.0
      base.merge(
        withheld:  @profile.ytd_withholding_state.to_f,
        set_aside: covered ? incremental.round(2) : nil,
        note: covered ?
          "ISO exercise-and-hold raises AMTI but not CA AGI, so the prior-year safe harbor holds — CA AMT is due April 15; set the cash aside" :
          "Withholding is below the CA prior-year safe harbor — estimated payments are weighted 30/40/0/30"
      )
    end
  end
end
