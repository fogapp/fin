# typed: strict

module Tax
  module Sections
    # The liability estimate: runs the federal engine and the profile's
    # state side over the assembled inputs, layers credits and payments per
    # jurisdiction, and reports bracket headroom. The state side is the CA
    # engine for California, the profile's entered projected state tax when
    # one is given (any state, CA included), or zero for a state without an
    # income tax (Tax::States). Null unless the profile is complete
    # (projected wages entered) and the engines it needs have tax
    # parameters for the year. Credits (adjustment kind "credit") reduce
    # each jurisdiction's net liability; "both" counts toward each side.
    class Liability < Base
      sig do
        params(deductions: T::Hash[Symbol, T.untyped], inputs: T::Hash[Symbol, Float],
               payments: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def build(deductions:, inputs:, payments:)
        current_profile = @context.profile
        return nil unless current_profile&.complete?

        salt_paid    = [ current_profile.salt_paid.to_f, deductions.dig(:salt, :amount) ].max
        state_source = current_profile.state_tax_source
        modeled      = state_source == States::Source::Modeled

        begin
          federal_params = Parameters.federal(@context.year)
          pair = JurisdictionPair.new(
            tax_year:       @context.year,
            filing_status:  current_profile.filing_status,
            wages:          inputs.fetch(:wages),
            other_ordinary: inputs.fetch(:other_ordinary),
            ltcg_qd:        inputs.fetch(:ltcg_qd),
            itemizing:      current_profile.itemizing,
            salt_paid:      salt_paid,
            itemized_other: current_profile.itemized_other,
            iso_spread:     inputs.fetch(:iso_spread)
          )
          federal_result = pair.federal
          state_result   = modeled ? pair.california : unmodeled_state_result(current_profile)
        rescue Parameters::Missing
          return nil
        end

        total_income = inputs.fetch(:wages) + inputs.fetch(:other_ordinary) + inputs.fetch(:ltcg_qd)
        federal      = jurisdiction_liability(federal_result, Jurisdiction::Federal, total_income,
                                              marginal_rate: pair.federal_marginal_ordinary_rate,
                                              paid: payments.dig(:federal, :total) +
                                                    @context.adjustments_total(TaxAdjustment::Kind::Payment, Jurisdiction::Federal))
        state        = jurisdiction_liability(state_result, Jurisdiction::State, total_income,
                                              marginal_rate: modeled ? pair.california_marginal_ordinary_rate : nil,
                                              paid: payments.dig(:state, :total) +
                                                    @context.adjustments_total(TaxAdjustment::Kind::Payment, Jurisdiction::State))

        {
          kind: "estimate",
          assumptions: {
            figures_status: {
              federal: Parameters.figures_status(:federal, @context.year).to_s,
              state:   modeled ? Parameters.figures_status(:california, @context.year).to_s : nil
            },
            notes: [
              "All dividends treated as qualified (LTCG/QD rates) until 1099s arrive",
              "ISO disqualifying dispositions not detected (v1)",
              "SALT input is max(profile SALT, computed state withholding + estimated payments)",
              "No NIIT, no Additional Medicare tax, MAGI approximated as modeled income",
              state_note(current_profile, state_source)
            ].compact
          },
          federal:         federal,
          state:           state,
          credits:         @context.adjustments_group(TaxAdjustment::Kind::Credit),
          total_liability: (federal[:total] - federal[:credits] +
                            state[:total] - state[:credits]).round(2),
          bracket_headroom: bracket_headroom(federal_params, federal_result, inputs, current_profile)
        }
      end

      private

      # The state side when no engine runs: the entered projected state
      # tax, or zero for a state without an income tax. Neither AMT nor
      # taxable income is modeled.
      sig { params(profile: TaxProfile).returns(T::Hash[Symbol, T.nilable(Float)]) }
      def unmodeled_state_result(profile)
        { regular_tax: profile.projected_state_tax.to_f.round(2), amt: 0.0, taxable_income: nil }
      end

      sig { params(profile: TaxProfile, source: States::Source).returns(T.nilable(String)) }
      def state_note(profile, source)
        name = States.name_for(profile.state)
        case source
        when States::Source::Modeled     then nil
        when States::Source::Entered     then "#{name} tax is the projected amount entered in the tax profile — no state AMT or marginal rate modeled"
        when States::Source::NoIncomeTax then "#{name} has no state income tax"
        else T.absurd(source)
        end
      end

      sig do
        params(result: T::Hash[Symbol, T.untyped], jurisdiction: Jurisdiction, total_income: Float,
               marginal_rate: T.nilable(Float), paid: Float).returns(T::Hash[Symbol, T.untyped])
      end
      def jurisdiction_liability(result, jurisdiction, total_income, marginal_rate:, paid:)
        total   = (result.fetch(:regular_tax) + result.fetch(:amt)).round(2)
        credits = @context.adjustments_total(TaxAdjustment::Kind::Credit, jurisdiction)
        net     = (total - credits).round(2)

        {
          regular_tax:            result.fetch(:regular_tax),
          amt:                    result.fetch(:amt),
          total:                  total,
          credits:                credits,
          taxable_income:         result.fetch(:taxable_income),
          effective_rate:         total_income.positive? ? (total / total_income).round(4) : 0.0,
          marginal_ordinary_rate: marginal_rate,
          withheld_and_paid:      paid.round(2),
          # Positive = projected refund; negative = projected amount owed.
          projected_refund_or_owed: (paid - net).round(2)
        }
      end

      sig do
        params(federal_params: T::Hash[Symbol, T.untyped], result: T::Hash[Symbol, Float],
               inputs: T::Hash[Symbol, Float], current_profile: TaxProfile)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def bracket_headroom(federal_params, result, inputs, current_profile)
        brackets = federal_params.dig(:ordinary_brackets, current_profile.filing_status)
        ordinary = [ result.fetch(:taxable_income) - inputs.fetch(:ltcg_qd), 0.0 ].max

        index = brackets.index { |(_rate, top)| top.nil? || ordinary < top } || (brackets.length - 1)
        current_rate, top = brackets.fetch(index)
        next_rate = brackets[index + 1]&.first

        ltcg_zero_top = federal_params.dig(:ltcg_brackets, current_profile.filing_status).first.last

        {
          to_next_federal_bracket: {
            amount:       top && (top - ordinary).round(2),
            current_rate: current_rate,
            next_rate:    next_rate
          },
          ltcg_zero_headroom: [ ltcg_zero_top - result.fetch(:taxable_income), 0.0 ].max.round(2),
          note: "Ordinary headroom is measured over ordinary taxable income; LTCG 0% headroom is room under the #{ltcg_zero_top} breakpoint over total taxable income. Estimates only."
        }
      end
    end
  end
end
