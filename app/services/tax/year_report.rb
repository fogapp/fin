# typed: strict

module Tax
  # The tax center's one rich assembler (docs/tax-center-design.md): builds
  # the full GET /api/v1/tax/report payload for a (household, year). Every
  # section carries a `kind` marker so the UI can never present an estimate
  # as a filing number:
  #
  #   "fact"     — computed deterministically from ledger data
  #   "record"   — user bookkeeping (payments made, checklist state)
  #   "estimate" — engine output under stated assumptions
  #
  # Date attribution: investment transactions by trade_date, cash by
  # transaction_date, equity events by occurred_on, transfers by the linked
  # transaction's date (to-side when present, else from-side).
  #
  # Documented v1 limitations (surfaced as notes in the payload):
  #   - all dividends are treated as qualified until 1099s arrive;
  #   - ISO disqualifying dispositions are not detected;
  #   - equity events without a share price are skipped (and counted);
  #   - mortgage interest is the amortization-walk split of linked payment
  #     transactions, sliced to the year — not a 1098 figure.
  #
  # Each section is built by its own service under Tax::Sections, all fed
  # one shared Sections::Context so profile/adjustments/payments load once.
  class YearReport
    extend T::Sig

    sig { params(household: Household, year: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def self.build(household:, year:)
      new(household: household, year: year).build
    end

    sig { params(household: Household, year: Integer).void }
    def initialize(household:, year:)
      @household = T.let(household, Household)
      @year      = T.let(year, Integer)
      @context   = T.let(Sections::Context.new(household: household, year: year), Sections::Context)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def build
      income     = Sections::Income.new(context: @context).build
      deductions = Sections::Deductions.new(context: @context).build
      inputs     = engine_inputs(income)
      payments   = Sections::Payments.new(context: @context).build(inputs)

      {
        year:          @year,
        generated_at:  Time.current.iso8601,
        profile:       @context.profile && Api::Render::TaxProfile.new.profile(T.must(@context.profile)),
        income:        income,
        deductions:    deductions,
        liability:     Sections::Liability.new(context: @context)
                                          .build(deductions: deductions, inputs: inputs, payments: payments),
        payments:      payments,
        contributions: Sections::Contributions.new(context: @context).build,
        flags:         Sections::Flags.new(context: @context).build,
        documents:     Sections::Documents.new(context: @context).build
      }
    end

    private

    # The assembled inputs shared by the liability estimate and the CA
    # safe-harbor AGI check. Facts stack on top of the profile's baselines;
    # dividends ride the LTCG/QD layer under the labeled qualified-dividend
    # assumption.
    sig { params(income: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, Float]) }
    def engine_inputs(income)
      profile = @context.profile
      other_ordinary = profile&.other_ordinary_income.to_f +
                       income[:interest] +
                       income.dig(:equity_comp, :ordinary_income) +
                       @context.adjustments_total(TaxAdjustment::Kind::Income, Jurisdiction::Federal)
      ltcg_qd = profile&.ltcg_qd_income.to_f +
                [ income.dig(:realized_gains, :long_term), 0.0 ].max +
                income[:dividends]

      {
        wages:          profile&.projected_wages.to_f,
        other_ordinary: other_ordinary.round(2),
        ltcg_qd:        ltcg_qd.round(2),
        iso_spread:     income.dig(:equity_comp, :iso_amt_spread)
      }
    end

    # The batched transfer-leg query-count spec exercises this seam
    # directly; the logic moved to Sections::Contributions, so keep a thin
    # private delegator rather than breaking that spec's target.
    sig { returns(T::Hash[T.untyped, Float]) }
    def transfer_contributions_by_account
      Sections::Contributions.new(context: @context).send(:transfer_contributions_by_account)
    end
  end
end
