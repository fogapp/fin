# typed: strict

module Tax
  # Federal income-tax engine for the exercise planner: regular tax
  # (ordinary brackets + LTCG/QD stacking), Form 6251 tentative minimum tax
  # (SALT/standard-deduction addback, ISO spread at line 2i, exemption with
  # 50% phaseout, Part III capital-gain rate preservation), and
  # AMT = max(0, TMT − regular).
  #
  # Approximations (documented, deliberate for v1):
  #   - MAGI ≈ wages + other_ordinary + ltcg_qd (no above-the-line detail).
  #   - Itemized deductions are SALT + a single `itemized_other` bucket.
  #   - No NIIT, no Additional Medicare tax, no AMT foreign tax credit.
  #
  # BigDecimal internally; floats at the API boundary.
  class Federal
    extend T::Sig

    sig do
      params(
        tax_year:       Integer,
        filing_status:  FilingStatus,
        wages:          T.untyped,
        other_ordinary: T.untyped,
        ltcg_qd:        T.untyped,
        itemizing:      T::Boolean,
        salt_paid:      T.untyped,
        itemized_other: T.untyped,
        iso_spread:     T.untyped
      ).void
    end
    def initialize(tax_year:, filing_status:, wages:, other_ordinary: 0, ltcg_qd: 0,
                   itemizing: false, salt_paid: 0, itemized_other: 0, iso_spread: 0)
      @params         = T.let(Parameters.federal(tax_year), T::Hash[Symbol, T.untyped])
      @filing_status  = T.let(filing_status, FilingStatus)
      @wages          = T.let(to_d(wages), BigDecimal)
      @other_ordinary = T.let(to_d(other_ordinary), BigDecimal)
      @ltcg_qd        = T.let(to_d(ltcg_qd), BigDecimal)
      @itemizing      = T.let(itemizing, T::Boolean)
      @salt_paid      = T.let(to_d(salt_paid), BigDecimal)
      @itemized_other = T.let(to_d(itemized_other), BigDecimal)
      @iso_spread     = T.let(to_d(iso_spread), BigDecimal)
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
        salt_used:      salt_used.to_f.round(2),
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

    # MAGI approximation: all modeled income (no above-the-line adjustments).
    sig { returns(BigDecimal) }
    def magi
      total_income
    end

    sig { returns(BigDecimal) }
    def standard_deduction
      BigDecimal(@params.dig(:standard_deduction, @filing_status))
    end

    # SALT cap phases down 30¢ per $ of MAGI over the start, to a floor.
    sig { returns(BigDecimal) }
    def salt_cap
      salt = @params.fetch(:salt)
      cap  = BigDecimal(salt[:cap]) -
             BigDecimal(salt[:phasedown_rate].to_s) * [ magi - BigDecimal(salt[:phasedown_start]), ZERO ].max
      [ cap, BigDecimal(salt[:floor]) ].max
    end

    sig { returns(BigDecimal) }
    def salt_allowed
      [ @salt_paid, salt_cap ].min
    end

    # Itemizing only wins when the itemized total beats the standard
    # deduction; otherwise we fall back to the standard deduction and no
    # SALT is "used" (so nothing is added back for AMT).
    sig { returns(T::Boolean) }
    def itemizing_used?
      @itemizing && (salt_allowed + @itemized_other) > standard_deduction
    end

    sig { returns(BigDecimal) }
    def salt_used
      itemizing_used? ? salt_allowed : ZERO
    end

    sig { returns(BigDecimal) }
    def deduction
      itemizing_used? ? salt_allowed + @itemized_other : standard_deduction
    end

    sig { returns(BigDecimal) }
    def taxable_income
      [ total_income - deduction, ZERO ].max
    end

    sig { returns(T::Array[[ Float, T.nilable(Integer) ]]) }
    def ordinary_brackets
      @params.dig(:ordinary_brackets, @filing_status)
    end

    sig { returns(T::Array[[ Float, T.nilable(Integer) ]]) }
    def ltcg_brackets
      @params.dig(:ltcg_brackets, @filing_status)
    end

    # Regular tax: ordinary brackets on the non-LTCG portion, LTCG/QD layer
    # stacked on top at 0/15/20% breakpoints.
    sig { returns(BigDecimal) }
    def regular_tax
      taxable   = taxable_income
      ordinary  = [ taxable - @ltcg_qd, ZERO ].max
      ltcg_part = taxable - ordinary

      Brackets.tax_on(ordinary, ordinary_brackets) +
        Brackets.stacked_layer_tax(ltcg_part, ordinary, ltcg_brackets)
    end

    # Form 6251: taxable income + the deduction addback (line 2a: SALT when
    # itemizing, otherwise the standard deduction) + the ISO spread (2i).
    sig { returns(BigDecimal) }
    def amti
      addback = itemizing_used? ? salt_used : standard_deduction
      taxable_income + addback + @iso_spread
    end

    sig { returns(BigDecimal) }
    def exemption
      amt = @params.fetch(:amt)
      base      = BigDecimal(amt.dig(:exemption, @filing_status))
      threshold = BigDecimal(amt.dig(:phaseout_threshold, @filing_status))
      reduction = BigDecimal(amt[:phaseout_rate].to_s) * [ amti - threshold, ZERO ].max
      [ base - reduction, ZERO ].max
    end

    # Tentative minimum tax with Part III capital-gain preservation: the
    # LTCG/QD layer keeps its 0/15/20 rates (stacked above the non-LTCG
    # excess); everything else pays 26% up to the breakpoint, 28% above.
    sig { returns(BigDecimal) }
    def tmt
      amt = @params.fetch(:amt)
      taxable_excess = [ amti - exemption, ZERO ].max
      return ZERO if taxable_excess <= 0

      ltcg_part = [ @ltcg_qd, taxable_excess ].min
      rest      = taxable_excess - ltcg_part

      breakpoint = BigDecimal(amt[:rate_breakpoint])
      low  = [ rest, breakpoint ].min * BigDecimal(amt[:rate_low].to_s)
      high = [ rest - breakpoint, ZERO ].max * BigDecimal(amt[:rate_high].to_s)

      low + high + Brackets.stacked_layer_tax(ltcg_part, rest, ltcg_brackets)
    end
  end
end
