# typed: strict

module Tax
  module Sections
    # Advisory flags: household-wide wash-sale findings. Warnings only —
    # realized gains in the income section are never silently adjusted.
    class Flags < Base
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build
        {
          kind:       "fact",
          wash_sales: WashSaleScanner.new(household: @context.household, year: @context.year).findings,
          note: "Wash-sale findings are warnings only — realized gains above are never silently adjusted"
        }
      end
    end
  end
end
