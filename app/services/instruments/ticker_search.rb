# typed: strict

module Instruments
  # On-demand ticker discovery for the market page: queries the provider's
  # symbol search for tickers we don't have a Security row for yet (the page's
  # local filter already surfaces known ones). Results are cached briefly —
  # symbol search is global market data and Alpha Vantage is rate-limited.
  class TickerSearch
    extend T::Sig

    # Alpha Vantage type → instrument class. Types outside this map (currencies,
    # indices) aren't trackable through the watch flow and are dropped.
    CLASS_MAP = T.let({
      "Equity"      => InstrumentClass::Equity,
      "ETF"         => InstrumentClass::Etf,
      "Mutual Fund" => InstrumentClass::MutualFund
    }.freeze, T::Hash[String, InstrumentClass])

    CACHE_TTL   = T.let(10.minutes, ActiveSupport::Duration)
    MAX_RESULTS = 8

    sig { params(query: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def call(query)
      q = query.to_s.strip
      return [] if q.length < 2
      return [] unless AlphaVantage.configured?

      matches = Rails.cache.fetch("ticker_search:#{q.downcase}", expires_in: CACHE_TTL) do
        AlphaVantage::Client.new.symbol_search(q)
      end

      tickers = matches.filter_map { |m| m[:ticker]&.upcase }
      known   = Security.where(ticker: tickers).pluck(:ticker).to_set

      # The provider interleaves foreign listings (NVD.DEX, NVDA34.SAO) and
      # loosely-related tickers with the primary one — rank exact-symbol and
      # US-market matches ahead of them rather than trusting provider order.
      q_up = q.upcase
      matches
        .select { |m| m[:ticker].present? && CLASS_MAP.key?(m[:security_type].to_s) }
        .reject { |m| known.include?(m[:ticker].upcase) }
        .sort_by { |m|
          [ m[:ticker].to_s.upcase == q_up ? 0 : 1,
            m[:region].to_s == "United States" ? 0 : 1,
            -m[:match_score].to_f ]
        }
        .first(MAX_RESULTS)
        .map { |m| m.merge(instrument_class: CLASS_MAP.fetch(m[:security_type])) }
    rescue AlphaVantage::Error => e
      Rails.logger.warn("[TickerSearch] provider search failed for #{q.inspect}: #{e.message}")
      []
    end
  end
end
