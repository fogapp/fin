# typed: strict

module Budgets
  module Stats
    extend T::Sig

    sig { params(values: T::Array[Numeric]).returns(Float) }
    def self.median(values)
      return 0.0 if values.empty?

      sorted = values.map(&:to_f).sort
      mid = sorted.size / 2
      sorted.size.odd? ? T.must(sorted[mid]) : (T.must(sorted[mid - 1]) + T.must(sorted[mid])) / 2.0
    end

    # Budgets look like budgets, not accounting: round up to the next $5.
    sig { params(amount: Numeric).returns(Integer) }
    def self.round_up5(amount)
      (amount.to_f / 5).ceil * 5
    end
  end
end
