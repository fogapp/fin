# typed: strict

module MarketData
  # Spends provider budgets by priority: held instruments first, then
  # watched, then curated benchmarks, then a one-time history backfill for
  # recently sold instruments (so valuations of the months they were held
  # are priced). Instruments in none of those tiers are dormant — never
  # synced, ending the every-ticker-ever-typed quota bleed.
  # Per-link exponential backoff keeps failing instruments from starving
  # healthy ones.
  class Scheduler
    extend T::Sig

    DEFAULT_BUDGETS = T.let({
      Provider::Tiingo => 45, # free tier allows 50 requests/hour
      Provider::AlphaVantage => 70,
      Provider::CoinGecko => 20,
      Provider::CoinMarketCap => 0 # quote-batch pipeline, not per-instrument candles
    }.freeze, T::Hash[Provider, Integer])

    Result = Struct.new(:synced, :skipped, :failed, keyword_init: true)

    sig { params(budgets: T::Hash[Provider, Integer], pace: T::Boolean).void }
    def initialize(budgets: DEFAULT_BUDGETS, pace: true)
      @budgets = T.let(budgets.dup, T::Hash[Provider, Integer])
      @pace    = T.let(pace, T::Boolean)
    end

    # One instrument through its pinned provider: a full history the first
    # time, the compact window after. Records link health and stamps
    # last_synced_at on success; errors propagate for the caller's policy
    # (the nightly run backs the link off, an on-demand job retries).
    sig { params(security: Security, link: InstrumentDataLink).returns(Integer) }
    def self.sync_candles!(security, link)
      provider = Router.provider_instance(T.unsafe(link).provider)
      # Custodian closes (CustodianPrices) aren't provider history: an
      # instrument priced only by its custodian still needs a full backfill.
      full = !Candle.where(security_id: security.id).where.not(source: CustodianPrices::SOURCE).exists?
      written = provider.sync_candles(security, link, full: full)
      link.record_success!
      security.update_column(:last_synced_at, Time.current)
      written
    end

    # Matched by name so referencing a provider's error class never forces a
    # Zeitwerk load (the classes live inside each provider's client file).
    RATE_LIMIT_ERRORS = T.let(%w[
      AlphaVantage::RateLimitError
      CoinGecko::Client::RateLimitError
      CoinMarketCap::RateLimitError
      Tiingo::RateLimitError
    ].freeze, T::Array[String])

    # A provider-wide quota condition, not the instrument's fault.
    sig { params(error: StandardError).returns(T::Boolean) }
    def self.rate_limit_error?(error)
      RATE_LIMIT_ERRORS.include?(error.class.name)
    end

    sig { returns(Result) }
    def run
      result = Result.new(synced: 0, skipped: 0, failed: 0)

      tiered = tiers
      links = Router.links_for(tiered.flatten, Capability::Candles)

      tiered.each do |securities|
        securities.each do |security|
          link = links[security.id]
          next if link.nil? || link.disabled?

          if link.in_backoff?
            result.skipped += 1
            next
          end

          provider_key = T.unsafe(link).provider
          budget = @budgets[provider_key].to_i
          next if budget <= 0

          # Decrement before syncing so a provider-wide rate limit inside
          # sync_one can zero the remaining budget without being overwritten.
          @budgets[provider_key] = budget - 1
          sync_one(security, link, result)
          pace_for(provider_key) if @budgets[provider_key].to_i > 0
        end
      end

      result
    end

    private

    # Tier membership, staleness-first within each tier. Runs unscoped —
    # instruments are shared market data, and with no Current.household the
    # position resolver sees every household's holdings.
    sig { returns(T::Array[T::Array[Security]]) }
    def tiers
      held_ids      = Positions::CurrentPositions.new.relation.distinct.pluck(:security_id)
      watched_ids   = SecurityWatch.unscoped.distinct.pluck(:security_id) - held_ids
      benchmark_ids = Security.unscoped
                              .where(ticker: MarketData::BENCHMARK_TICKERS)
                              .where.not(instrument_class: Instruments::InstrumentClass::Crypto)
                              .ids - held_ids - watched_ids

      [ held_ids, watched_ids, benchmark_ids, recently_sold_ids(held_ids + watched_ids + benchmark_ids) ].map do |ids|
        Security.unscoped.where(id: ids).with_ticker
                .order(Arel.sql("last_synced_at ASC NULLS FIRST")).to_a
      end
    end

    # How far back a sold instrument still matters: valuation charts and
    # net-worth history reach about this far.
    RECENTLY_SOLD_WINDOW = T.let(2.years, ActiveSupport::Duration)

    # Instruments traded within RECENTLY_SOLD_WINDOW that no longer sit in any
    # other tier and have no provider history yet. Once a full sync lands
    # they drop out, so this tier costs each instrument one request.
    sig { params(exclude: T::Array[String]).returns(T::Array[String]) }
    def recently_sold_ids(exclude)
      ids = InvestmentTransaction.unscoped
        .joins(:transaction_type)
        .where(transaction_types: { category: Positions::Rebuild::POSITION_CATEGORIES })
        .where(trade_date: (Date.current - RECENTLY_SOLD_WINDOW)..)
        .where.not(security_id: nil)
        .distinct.pluck(:security_id) - exclude
      return [] if ids.empty?

      ids -= Candle.daily.where(security_id: ids).where.not(source: CustodianPrices::SOURCE).distinct.pluck(:security_id)
      # A provider that answered with nothing (a delisted ticker) won't do
      # better tomorrow; don't spend a request on it every night.
      ids - InstrumentDataLink.where(security_id: ids, capability: Capability::Candles)
                              .where.not(last_success_at: nil).pluck(:security_id)
    end

    sig { params(security: Security, link: InstrumentDataLink, result: T.untyped).void }
    def sync_one(security, link, result)
      provider_key = T.unsafe(link).provider
      self.class.sync_candles!(security, link)
      result.synced += 1
    rescue => e
      if self.class.rate_limit_error?(e)
        # Provider-wide condition, not this instrument's fault: zero the
        # provider's remaining budget for the run and do NOT record_failure!
        # — that would push every remaining healthy instrument into
        # exponential backoff. last_synced_at stays untouched so staleness
        # stays visible.
        @budgets[provider_key] = 0
        result.skipped += 1
        Rails.logger.warn("[MarketData::Scheduler] #{provider_key} rate limited; skipping its remaining budget: #{e.message}")
      else
        # Per-instrument failure: back the link off, but never touch
        # last_synced_at — the link's last_attempt_at already tracks
        # attempts, and stamping sync time on failure masked staleness in
        # the drift UI.
        link.record_failure!(e.message)
        result.failed += 1
        Rails.logger.warn("[MarketData::Scheduler] #{security.ticker} via #{provider_key} failed: #{e.class}: #{e.message}")
      end
    end

    PACING = T.let({ Provider::AlphaVantage => 1.0, Provider::CoinGecko => 6.0,
                     Provider::Tiingo => 1.0 }.freeze,
                   T::Hash[Provider, Float])

    sig { params(provider: Provider).void }
    def pace_for(provider)
      return unless @pace

      delay = PACING[provider]
      sleep(delay) if delay
    end
  end
end
