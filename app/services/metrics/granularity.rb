# typed: strict

module Metrics
  # Period size of a metric's series points.
  class Granularity < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Month = new("month")
      Day = new("day")
    end
  end
end
