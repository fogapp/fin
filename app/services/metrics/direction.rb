# typed: strict

module Metrics
  # Which way "good" points for coloring changes in the UI.
  class Direction < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      UpGood = new("up_good")
      DownGood = new("down_good")
      Neutral = new("neutral")
    end
  end
end
