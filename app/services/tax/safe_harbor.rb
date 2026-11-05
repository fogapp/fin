# typed: strict

module Tax
  # Prior-year safe-harbor evaluation, shared by the exercise planner and
  # the tax-center year report: required annual prepayment is 100% of
  # prior-year tax (110% over the high-AGI threshold), compared against
  # whatever the caller counts as paid (withholding alone for the planner;
  # withholding + estimated payments for the year report). California adds
  # the $1M current-year AGI ceiling, above which the prior-year harbor is
  # unavailable entirely.
  module SafeHarbor
    extend T::Sig

    sig { params(profile: TaxProfile, tax_year: Integer, paid: Float).returns(T::Hash[Symbol, T.untyped]) }
    def self.federal(profile:, tax_year:, paid:)
      evaluate(profile: profile, paid: paid, rules: Parameters.federal(tax_year).fetch(:safe_harbor))
    end

    sig do
      params(profile: TaxProfile, tax_year: Integer, paid: Float, current_agi: Float)
        .returns(T::Hash[Symbol, T.untyped])
    end
    def self.california(profile:, tax_year:, paid:, current_agi:)
      rules = Parameters.california(tax_year).fetch(:estimated_tax)

      if current_agi >= rules[:safe_harbor_agi_ceiling]
        return {
          status:              "unavailable",
          current_agi:         current_agi.round(2),
          installment_weights: rules[:installment_weights],
          note: "CA prior-year safe harbor is unavailable when current-year CA AGI is $1M or more — estimated payments (30/40/0/30) are required"
        }
      end

      evaluate(profile: profile, paid: paid, rules: rules)
        .merge(current_agi: current_agi.round(2), installment_weights: rules[:installment_weights])
    end

    # Shared core: unknown without prior-year tax; otherwise covered iff
    # `paid` meets the multiplied prior-year liability.
    sig do
      params(profile: TaxProfile, paid: Float, rules: T::Hash[Symbol, T.untyped])
        .returns(T::Hash[Symbol, T.untyped])
    end
    def self.evaluate(profile:, paid:, rules:)
      prior_tax = profile.prior_year_total_tax
      if prior_tax.nil?
        return { status: "unknown",
                 note: "Enter last year's total tax to check the prior-year safe harbor" }
      end

      multiplier = profile.prior_year_agi.to_d > rules[:high_agi_threshold] ?
                     BigDecimal(rules[:prior_year_multiplier_high_agi].to_s) : BigDecimal("1")
      required = (prior_tax.to_d * multiplier).to_f
      covered  = paid >= required

      {
        status:          covered ? "covered" : "uncovered",
        required_annual: required.round(2),
        paid:            paid.round(2)
      }
    end
  end
end
