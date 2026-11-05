# typed: strict

module MarketData
  # The market-data providers the router can pin to an instrument
  # capability. Serialized values are the strings instrument_data_links
  # stores and the scheduler budgets/pacing tables key on.
  class Provider < T::Enum
    include ApplicationEnum

    enums do
      AlphaVantage = new("alpha_vantage")
      CoinGecko = new("coin_gecko")
      CoinMarketCap = new("coin_market_cap")
      Tiingo = new("tiingo")
    end
  end
end
