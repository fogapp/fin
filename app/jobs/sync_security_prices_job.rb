# typed: true

# On-demand price sync for one instrument (a newly watched security, a
# benchmark with no history, a manual refresh). Goes through the same
# router-pinned provider as the nightly MarketData::Scheduler, so the
# instrument's candles come from wherever its link points — Tiingo when
# configured, Alpha Vantage otherwise, a crypto source for crypto.
class SyncSecurityPricesJob < ApplicationJob
  extend T::Sig

  queue_as :market_data

  MAX_RATE_LIMIT_ATTEMPTS = 5
  RATE_LIMIT_WAIT = 60.seconds

  sig { params(security_id: String).void }
  def perform(security_id)
    security = Security.find(security_id)
    link = MarketData::Router.link_for(security, MarketData::Capability::Candles)
    if link.nil? || link.disabled?
      Rails.logger.info("[SyncSecurityPricesJob] #{security.ticker}: no enabled candle provider; skipping")
      return
    end

    sync(security, link)
  end

  private

  sig { params(security: Security, link: InstrumentDataLink).void }
  def sync(security, link)
    written = MarketData::Scheduler.sync_candles!(security, link)
    Rails.logger.info("[SyncSecurityPricesJob] #{security.ticker} via #{T.unsafe(link).provider.serialize}: #{written} candles")
  rescue => e
    if MarketData::Scheduler.rate_limit_error?(e)
      # Provider-wide quota: retry with a bounded wait rather than backing
      # this instrument's link off (a persistent 429 — e.g. an expired plan
      # — must not re-enqueue forever).
      if executions < MAX_RATE_LIMIT_ATTEMPTS
        Rails.logger.warn("[SyncSecurityPricesJob] rate limited for #{security.ticker}, retrying in 60s (attempt #{executions}/#{MAX_RATE_LIMIT_ATTEMPTS})")
        retry_job wait: RATE_LIMIT_WAIT
      else
        Rails.logger.error("[SyncSecurityPricesJob] rate limited for #{security.ticker}; giving up after #{executions} attempts: #{e.message}")
      end
    else
      # Same per-instrument policy as the nightly run: back the link off and
      # leave last_synced_at alone so staleness stays visible.
      link.record_failure!(e.message)
      Rails.logger.warn("[SyncSecurityPricesJob] #{security.ticker} failed: #{e.class}: #{e.message}")
    end
  end
end
