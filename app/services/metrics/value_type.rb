# typed: strict

module Metrics
  # Flow (a per-period sum, pace-adjustable mid-period) vs level (a point-in-
  # time valuation).
  class ValueType < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Flow = new("flow")
      Level = new("level")
    end
  end
end
