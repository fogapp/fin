# typed: strict

module Tax
  # California income-tax engine for the exercise planner: regular tax
  # (brackets + the 1% Behavioral Health Services Tax over $1M taxable) and
  # CA AMT per Schedule P (7% flat rate, exemption with 25¢/$ phaseout,
  # standard-deduction addback, FTB Pub 1004 ISO-spread treatment).
  #
  # CA has no LTCG preference — `ltcg_qd` is simply more ordinary income.
  #
  # Exclusions (documented, deliberate for v1): CA itemized deductions are
  # not modeled (the CA standard deduction is always used), no SDI, no
  # mental-health credits.
  class California
    extend T::Sig

    sig do
      params(
        tax_year:       Integer,
        filing_status:  FilingStatus,
        wages:          T.untyped,
        other_ordinary: T.untyped,
        ltcg_qd:        T.untyped,
        iso_spread:     T.untyped
      ).void
    end
    def initialize(tax_year:, filing_status:, wages:, other_ordinary: 0, ltcg_qd: 0, iso_spread: 0)
      @params        = T.let(Parameters.california(tax_year), T::Hash[Symbol, T.untyped])
      @filing_status = filing_status
      @wages         = T.let(to_d(wages), BigDecimal)
      @other_ordinary = T.let(to_d(other_ordinary), BigDecimal)
      @ltcg_qd       = T.let(to_d(ltcg_qd), BigDecimal)
      @iso_spread    = T.let(to_d(iso_spread), BigDecimal)
    end

    sig { returns(T::Hash[Symbol, Float]) }
    def call
      regular = regular_tax
      tmt_amount = tmt

      {
        regular_tax:    regular.to_f.round(2),
        tmt:            tmt_amount.to_f.round(2),
        amt:            [ tmt_amount - regular, BigDecimal("0") ].max.to_f.round(2),
        amti:           amti.to_f.round(2),
        exemption:      exemption.to_f.round(2),
        taxable_income: taxable_income.to_f.round(2)
      }
    end

    private

    ZERO = T.let(BigDecimal("0"), BigDecimal)

    sig { params(value: T.untyped).returns(BigDecimal) }
    def to_d(value)
      BigDecimal(value.to_s.presence || "0")
    end

    sig { returns(BigDecimal) }
    def total_income
      @wages + @other_ordinary + @ltcg_qd
    end

    sig { returns(BigDecimal) }
    def standard_deduction
      BigDecimal(@params.dig(:standard_deduction, @filing_status))
    end

    sig { returns(BigDecimal) }
    def taxable_income
      [ total_income - standard_deduction, ZERO ].max
    end

    # Brackets + 1% BHST on taxable income over $1M.
    sig { returns(BigDecimal) }
    def regular_tax
      taxable = taxable_income
      bhst    = @params.fetch(:bhst)
      surtax  = [ taxable - BigDecimal(bhst[:threshold]), ZERO ].max * BigDecimal(bhst[:rate].to_s)

      Brackets.tax_on(taxable, @params.dig(:ordinary_brackets, @filing_status)) + surtax
    end

    # Schedule P AMTI: taxable income + the standard-deduction addback +
    # the ISO spread (Pub 1004: treated as NSO income for CA AMT).
    sig { returns(BigDecimal) }
    def amti
      taxable_income + standard_deduction + @iso_spread
    end

    sig { returns(BigDecimal) }
    def exemption
      amt = @params.fetch(:amt)
      base      = BigDecimal(amt.dig(:exemption, @filing_status))
      threshold = BigDecimal(amt.dig(:phaseout_threshold, @filing_status))
      reduction = BigDecimal(amt[:phaseout_rate].to_s) * [ amti - threshold, ZERO ].max
      [ base - reduction, ZERO ].max
    end

    sig { returns(BigDecimal) }
    def tmt
      rate = BigDecimal(@params.dig(:amt, :rate).to_s)
      [ amti - exemption, ZERO ].max * rate
    end
  end
end
