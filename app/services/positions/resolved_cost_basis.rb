# typed: strict

module Positions
  # Which cost basis a held position reports, in one place. The portfolio,
  # security and cost-basis pages each used to decide this themselves (a 95%
  # lot threshold with a computed fallback, the same threshold without the
  # fallback, and "any lot wins"), so one security could show three bases.
  #
  # Precedence:
  #   1. Manual lots, when they cover at least LOT_COVERAGE_THRESHOLD of the
  #      held quantity (a lot covering 10 of 500 shares must not replace the
  #      whole basis).
  #   2. The snapshot's own basis, when it carries one.
  #   3. Average cost from the transaction ledger (CostBasisCalculator) —
  #      e.g. synthesized Coinbase positions, whose snapshots carry 0.
  #   4. Otherwise the snapshot's 0, reported as Source::None.
  class ResolvedCostBasis
    extend T::Sig

    LOT_COVERAGE_THRESHOLD = 0.95

    class Source < T::Enum
      enums do
        Lots     = new("lots")
        Snapshot = new("snapshot")
        Computed = new("computed")
        None     = new("none")
      end
    end

    class Result < T::Struct
      const :cost_basis, Float
      const :source, Source
      # Share of the held quantity the manual lots cover (0.0 with no lots).
      const :lot_coverage, Float
    end

    sig { params(security_ids: T::Array[T.untyped]).void }
    def initialize(security_ids)
      @security_ids = T.let(security_ids, T::Array[T.untyped])
      @lot_totals   = T.let(::InvestmentLot.totals_by_security(security_ids), T::Hash[T.untyped, T::Hash[Symbol, Float]])
      @calculator   = T.let(nil, T.nilable(CostBasisCalculator))
    end

    # True when lots cover enough of `quantity` to stand in for its basis.
    # Shared with the cost-basis page's status column so "complete" there
    # means exactly "the other pages use these lots".
    sig { params(coverage: Float).returns(T::Boolean) }
    def self.covered?(coverage)
      coverage >= LOT_COVERAGE_THRESHOLD
    end

    sig { params(security_id: T.untyped, quantity: Float).returns(Float) }
    def lot_coverage(security_id, quantity:)
      totals = @lot_totals[security_id]
      return 0.0 unless totals && quantity.positive?

      T.must(totals[:quantity]) / quantity
    end

    sig { params(security_id: T.untyped, quantity: Float, snapshot_cost_basis: Float).returns(Result) }
    def resolve(security_id, quantity:, snapshot_cost_basis:)
      coverage = lot_coverage(security_id, quantity: quantity)

      if self.class.covered?(coverage)
        return Result.new(cost_basis: T.must(T.must(@lot_totals[security_id])[:cost_basis]),
                          source: Source::Lots, lot_coverage: coverage)
      end

      if snapshot_cost_basis.nonzero?
        return Result.new(cost_basis: snapshot_cost_basis, source: Source::Snapshot, lot_coverage: coverage)
      end

      computed = calculator.coverage(security_id, current_quantity: quantity)&.cost_basis
      if computed
        Result.new(cost_basis: computed, source: Source::Computed, lot_coverage: coverage)
      else
        Result.new(cost_basis: snapshot_cost_basis, source: Source::None, lot_coverage: coverage)
      end
    end

    private

    # Only built when some position actually needs the ledger fallback.
    sig { returns(CostBasisCalculator) }
    def calculator
      @calculator ||= CostBasisCalculator.new(@security_ids)
    end
  end
end
