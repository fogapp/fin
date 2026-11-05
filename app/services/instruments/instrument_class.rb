# typed: strict

module Instruments
  # The instrument taxonomy the resolver keys identity on (crypto uses the
  # crypto_symbol scheme, everything else the ticker scheme) and the router
  # uses to pick default providers.
  class InstrumentClass < T::Enum
    include ApplicationEnum

    enums do
      Equity = new("equity")
      Etf = new("etf")
      MutualFund = new("mutual_fund")
      Bond = new("bond")
      CashEquivalent = new("cash_equivalent")
      Crypto = new("crypto")
      Commodity = new("commodity")
      Option = new("option")
      Fx = new("fx")
      RealAsset = new("real_asset")
      Other = new("other")
    end
  end
end
