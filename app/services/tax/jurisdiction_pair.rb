# typed: strict

module Tax
  # One (federal, california) engine run over a single set of modeled
  # inputs, plus the marginal ordinary-rate lookups both engines' callers
  # kept re-deriving. Shared by the year report's liability section and the
  # exercise planner so the pairing (and the CA BHST marginal handling)
  # lives in exactly one place.
  #
  # Engine results are memoized: the pair is cheap to hold and each engine
  # runs at most once. Parameters::Missing raises lazily on first use, so
  # callers keep their own rescue semantics.
  class JurisdictionPair
    extend T::Sig

    sig do
      params(
        tax_year:       Integer,
        filing_status:  FilingStatus,
        wages:          T.untyped,
        other_ordinary: T.untyped,
        ltcg_qd:        T.untyped,
        iso_spread:     T.untyped,
        itemizing:      T::Boolean,
        salt_paid:      T.untyped,
        itemized_other: T.untyped
      ).void
    end
    def initialize(tax_year:, filing_status:, wages:, other_ordinary: 0, ltcg_qd: 0,
                   iso_spread: 0, itemizing: false, salt_paid: 0, itemized_other: 0)
      @tax_year       = tax_year
      @filing_status  = filing_status
      @wages          = wages
      @other_ordinary = other_ordinary
      @ltcg_qd        = ltcg_qd
      @iso_spread     = iso_spread
      @itemizing      = itemizing
      @salt_paid      = salt_paid
      @itemized_other = itemized_other
      @federal        = T.let(nil, T.nilable(T::Hash[Symbol, Float]))
      @california     = T.let(nil, T.nilable(T::Hash[Symbol, Float]))
    end

    sig { returns(T::Hash[Symbol, Float]) }
    def federal
      @federal ||= Federal.new(
        tax_year:       @tax_year,
        filing_status:  @filing_status,
        wages:          @wages,
        other_ordinary: @other_ordinary,
        ltcg_qd:        @ltcg_qd,
        itemizing:      @itemizing,
        salt_paid:      @salt_paid,
        itemized_other: @itemized_other,
        iso_spread:     @iso_spread
      ).call
    end

    sig { returns(T::Hash[Symbol, Float]) }
    def california
      # CA models no itemized deductions (engine doc) — the federal-only
      # inputs are deliberately not forwarded.
      @california ||= California.new(
        tax_year:       @tax_year,
        filing_status:  @filing_status,
        wages:          @wages,
        other_ordinary: @other_ordinary,
        ltcg_qd:        @ltcg_qd,
        iso_spread:     @iso_spread
      ).call
    end

    # Marginal federal rate on the next ordinary dollar: ordinary taxable
    # income is total taxable minus the LTCG/QD layer (which stacks on top).
    sig { returns(Float) }
    def federal_marginal_ordinary_rate
      params   = Parameters.federal(@tax_year)
      taxable  = BigDecimal(federal.fetch(:taxable_income).to_s)
      ordinary = [ taxable - @ltcg_qd.to_d, BigDecimal("0") ].max
      Brackets.marginal_rate(ordinary, params.dig(:ordinary_brackets, @filing_status)).to_f
    end

    # Marginal CA rate on the next ordinary dollar, including the 1% BHST
    # once taxable income crosses its threshold (CA has no LTCG preference).
    sig { returns(Float) }
    def california_marginal_ordinary_rate
      params  = Parameters.california(@tax_year)
      taxable = BigDecimal(california.fetch(:taxable_income).to_s)
      rate = Brackets.marginal_rate(taxable, params.dig(:ordinary_brackets, @filing_status))
      rate += BigDecimal(params.dig(:bhst, :rate).to_s) if taxable >= BigDecimal(params.dig(:bhst, :threshold))
      rate.to_f
    end
  end
end
