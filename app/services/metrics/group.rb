# typed: strict

module Metrics
  # Stats-page section a metric lives under.
  class Group < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Cashflow = new("cashflow")
      Investments = new("investments")
      NetWorth = new("net_worth")
    end
  end
end
