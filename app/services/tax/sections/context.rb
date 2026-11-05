# typed: strict

module Tax
  module Sections
    # The shared, memoized data every report section draws from: the
    # (household, year) pair, the year's date range, and the lazily loaded
    # profile / adjustments / estimated payments. Sections receive ONE
    # context so shared records are fetched once per report build, never
    # once per section.
    class Context
      extend T::Sig

      sig { returns(Household) }
      attr_reader :household

      sig { returns(Integer) }
      attr_reader :year

      sig { returns(T::Range[Date]) }
      attr_reader :range

      sig { params(household: Household, year: Integer).void }
      def initialize(household:, year:)
        @household = T.let(household, Household)
        @year      = T.let(year, Integer)
        @range     = T.let(Date.new(year, 1, 1)..Date.new(year, 12, 31), T::Range[Date])
        @profile            = T.let(nil, T.nilable(TaxProfile))
        @profile_loaded     = T.let(false, T::Boolean)
        @adjustments        = T.let(nil, T.nilable(T::Array[TaxAdjustment]))
        @estimated_payments = T.let(nil, T.nilable(T::Array[EstimatedTaxPayment]))
        @renderer           = T.let(nil, T.nilable(Api::Render::Tax))
      end

      sig { returns(T.nilable(TaxProfile)) }
      def profile
        return @profile if @profile_loaded

        @profile_loaded = true
        @profile = TaxProfile.where(household_id: @household.id).find_by(tax_year: @year)
      end

      sig { returns(T::Array[TaxAdjustment]) }
      def adjustments
        @adjustments ||= TaxAdjustment.where(household_id: @household.id, tax_year: @year)
                                      .order(:created_at).to_a
      end

      sig { returns(T::Array[EstimatedTaxPayment]) }
      def estimated_payments
        @estimated_payments ||= EstimatedTaxPayment.where(household_id: @household.id, tax_year: @year)
                                                   .order(:paid_on, :created_at).to_a
      end

      sig { returns(Api::Render::Tax) }
      def renderer
        @renderer ||= Api::Render::Tax.new
      end

      sig { returns(T.untyped) }
      def investment_transactions
        InvestmentTransaction.where(household_id: @household.id, trade_date: @range)
      end

      # Adjustments of `kind` counting toward a jurisdiction (Both counts
      # toward each side).
      sig { params(kind: TaxAdjustment::Kind, jurisdiction: Jurisdiction).returns(Float) }
      def adjustments_total(kind, jurisdiction)
        adjustments.select { |a| a.kind == kind && [ jurisdiction, Jurisdiction::Both ].include?(a.jurisdiction) }
                   .sum(0.0) { |a| a.amount.to_f }.round(2).to_f
      end

      sig { params(kind: TaxAdjustment::Kind).returns(T::Hash[Symbol, T.untyped]) }
      def adjustments_group(kind)
        items = adjustments.select { |a| a.kind == kind }
        {
          kind:  "record",
          total: items.sum(0.0) { |a| a.amount.to_f }.round(2),
          items: items.map { |a| renderer.adjustment(a) }
        }
      end
    end
  end
end
