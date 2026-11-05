# typed: strict

module Tax
  module Sections
    # Payment records: withholding + estimated payments per jurisdiction,
    # the derived due-date windows, and the safe-harbor check (which needs
    # the engine inputs for the CA current-AGI rule). The state side follows
    # the profile's state: no due dates or safe harbor for a state without
    # an income tax, and the safe harbor is only checked for California.
    class Payments < Base
      sig { params(inputs: T::Hash[Symbol, Float]).returns(T::Hash[Symbol, T.untyped]) }
      def build(inputs)
        federal_records = @context.estimated_payments.select { |p| p.jurisdiction == Jurisdiction::Federal }
        state_records   = @context.estimated_payments.select { |p| p.jurisdiction == Jurisdiction::State }

        federal_withholding = @context.profile&.ytd_withholding_federal.to_f
        state_withholding   = @context.profile&.ytd_withholding_state.to_f

        {
          kind: "record",
          federal: jurisdiction_payments(federal_withholding, federal_records),
          state:   jurisdiction_payments(state_withholding, state_records),
          due_dates: due_dates(federal_records, state_records),
          safe_harbor: safe_harbor(inputs,
                                   paid_federal: paid_total(federal_withholding, federal_records, Jurisdiction::Federal),
                                   paid_state:   paid_total(state_withholding, state_records, Jurisdiction::State))
        }
      end

      private

      sig { params(withholding: Float, records: T::Array[EstimatedTaxPayment]).returns(T::Hash[Symbol, T.untyped]) }
      def jurisdiction_payments(withholding, records)
        estimated_total = records.sum(0.0) { |p| p.amount.to_f }
        {
          withholding: withholding.round(2),
          estimated:   records.map { |p| @context.renderer.estimated_payment(p) },
          total:       (withholding + estimated_total).round(2)
        }
      end

      sig { params(withholding: Float, records: T::Array[EstimatedTaxPayment], jurisdiction: Jurisdiction).returns(Float) }
      def paid_total(withholding, records, jurisdiction)
        (withholding + records.sum(0.0) { |p| p.amount.to_f } +
          @context.adjustments_total(TaxAdjustment::Kind::Payment, jurisdiction)).round(2).to_f
      end

      sig do
        params(federal_records: T::Array[EstimatedTaxPayment], state_records: T::Array[EstimatedTaxPayment])
          .returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def due_dates(federal_records, state_records)
        today = Date.current

        schedules = { "federal" => [ federal_records, DueDates::FEDERAL_WEIGHTS ] }
        schedules["state"] = [ state_records, state_weights ] unless no_state_income_tax?

        schedules.flat_map do |jurisdiction, (records, weights)|
          DueDates.for_year(@context.year).each_with_index.map do |entry, index|
            window = entry.fetch(:window)
            {
              jurisdiction:   jurisdiction,
              label:          entry.fetch(:label),
              date:           entry.fetch(:date).iso8601,
              weight:         weights[index],
              paid_in_window: records.select { |p| window.cover?(p.paid_on) }.sum(0.0) { |p| p.amount.to_f }.round(2),
              status:         entry.fetch(:date) < today ? "past" : "upcoming"
            }
          end
        end
      end

      sig { params(inputs: T::Hash[Symbol, Float], paid_federal: Float, paid_state: Float).returns(T::Hash[Symbol, T.untyped]) }
      def safe_harbor(inputs, paid_federal:, paid_state:)
        current_profile = @context.profile
        if current_profile.nil?
          missing = { status: "unknown", note: "No tax profile for #{@context.year}" }
          return { federal: missing, state: missing }
        end

        current_agi = inputs.fetch(:wages) + inputs.fetch(:other_ordinary) + inputs.fetch(:ltcg_qd)

        federal = begin
          SafeHarbor.federal(profile: current_profile, tax_year: @context.year, paid: paid_federal)
        rescue Parameters::Missing => e
          { status: "unknown", note: e.message }
        end

        { federal: federal, state: state_safe_harbor(current_profile, paid: paid_state, current_agi: current_agi) }
      end

      sig { params(profile: TaxProfile, paid: Float, current_agi: Float).returns(T::Hash[Symbol, T.untyped]) }
      def state_safe_harbor(profile, paid:, current_agi:)
        if no_state_income_tax?
          return { status: "not_applicable", note: "#{States.name_for(profile.state)} has no state income tax" }
        end
        unless profile.state == States::CALIFORNIA
          return { status: "unknown", note: "The state safe harbor is only checked for California" }
        end

        SafeHarbor.california(profile: profile, tax_year: @context.year, paid: paid, current_agi: current_agi)
      rescue Parameters::Missing => e
        { status: "unknown", note: e.message }
      end

      # California weights installments 30/40/0/30; other states are assumed
      # to follow the federal even quarters, as most do.
      sig { returns(T::Array[Float]) }
      def state_weights
        state = @context.profile&.state
        state.nil? || state == States::CALIFORNIA ? DueDates::STATE_WEIGHTS : DueDates::FEDERAL_WEIGHTS
      end

      sig { returns(T::Boolean) }
      def no_state_income_tax?
        @context.profile&.state_tax_source == States::Source::NoIncomeTax
      end
    end
  end
end
