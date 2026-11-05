# typed: true

class SyncSecurityNewsJob < ApplicationJob
  extend T::Sig

  queue_as :market_data

  sig { params(security_id: T.nilable(String)).void }
  def perform(security_id = nil)
    return unless AlphaVantage.configured?

    # News articles are shared market data — sync anything any household watches.
    securities = security_id \
      ? Security.where(id: security_id) \
      : Security.watched_by_anyone.with_ticker

    # Deliberately not AlphaVantageRetries#with_alpha_vantage: this job loops
    # over many securities, so a 429 breaks out of the loop (the rest would
    # just 429 too) instead of retrying the whole job.
    securities.each do |security|
      count = SecurityNewsSyncer.new(security).call
      Rails.logger.info("[SyncSecurityNewsJob] #{security.ticker}: #{count} articles synced")
    rescue AlphaVantage::RateLimitError => e
      Rails.logger.warn("[SyncSecurityNewsJob] rate limited on #{security.ticker}: #{e.message}")
      break
    rescue AlphaVantage::Error => e
      Rails.logger.error("[SyncSecurityNewsJob] #{security.ticker} failed: #{e.message}")
    end
  end
end
