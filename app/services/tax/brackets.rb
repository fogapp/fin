# typed: strict

module Tax
  # Shared piecewise-bracket math. Brackets are [rate, top] pairs over
  # taxable income with a nil top on the final bracket. All arithmetic is
  # BigDecimal; callers convert to Float only at the API boundary.
  module Brackets
    extend T::Sig

    sig { params(amount: BigDecimal, brackets: T::Array[[ Float, T.nilable(Integer) ]]).returns(BigDecimal) }
    def self.tax_on(amount, brackets)
      return BigDecimal("0") if amount <= 0

      tax   = BigDecimal("0")
      floor = BigDecimal("0")
      brackets.each do |rate, top|
        ceiling = top.nil? ? amount : [ amount, BigDecimal(top) ].min
        break if ceiling <= floor

        tax += (ceiling - floor) * BigDecimal(rate.to_s)
        floor = ceiling
      end
      tax
    end

    # The bracket rate applying to the next dollar above `amount`.
    sig { params(amount: BigDecimal, brackets: T::Array[[ Float, T.nilable(Integer) ]]).returns(BigDecimal) }
    def self.marginal_rate(amount, brackets)
      brackets.each do |rate, top|
        return BigDecimal(rate.to_s) if top.nil? || amount < BigDecimal(top)
      end
      BigDecimal(T.must(brackets.last).first.to_s)
    end

    # Tax on a preferential-rate layer (LTCG/QD) stacked on top of an
    # ordinary layer: the layer occupies [ordinary_base, ordinary_base +
    # layer_amount) against rate breakpoints defined over total taxable
    # income.
    sig do
      params(layer_amount: BigDecimal, ordinary_base: BigDecimal,
             brackets: T::Array[[ Float, T.nilable(Integer) ]]).returns(BigDecimal)
    end
    def self.stacked_layer_tax(layer_amount, ordinary_base, brackets)
      return BigDecimal("0") if layer_amount <= 0

      total = ordinary_base + layer_amount
      tax   = BigDecimal("0")
      floor = ordinary_base
      brackets.each do |rate, top|
        ceiling = top.nil? ? total : [ total, BigDecimal(top) ].min
        next if ceiling <= floor

        tax += (ceiling - floor) * BigDecimal(rate.to_s)
        floor = ceiling
        break if floor >= total
      end
      tax
    end
  end
end
