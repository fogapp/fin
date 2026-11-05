# typed: strict

module Metrics
  # How a metric's values render: dollars, a bare count, or percent points.
  class Unit < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Currency = new("currency")
      Count = new("count")
      Percent = new("percent")
    end
  end
end
