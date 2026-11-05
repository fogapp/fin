# typed: strict

module MarketData
  # What a provider link supplies for an instrument: daily candles, spot
  # quotes, company metadata, or news. One instrument_data_links row exists
  # per (instrument, capability).
  class Capability < T::Enum
    include ApplicationEnum

    enums do
      Candles = new("candles")
      Quotes = new("quotes")
      Metadata = new("metadata")
      News = new("news")
    end
  end
end
