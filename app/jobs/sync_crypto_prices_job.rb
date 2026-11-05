# typed: true

class SyncCryptoPricesJob < ApplicationJob
  extend T::Sig

  queue_as :market_data
  # Coinbase/Alchemy syncs and the recurring schedule all enqueue this job —
  # serialize on one key so completions don't stack up concurrent
  # CoinMarketCap calls.
  limits_concurrency to: 1, key: ->(*) { "crypto_prices" }

  # A CMC 429 is provider-wide: retry the whole (idempotent) job with backoff
  # instead of burning through the remaining households.
  retry_on CoinMarketCap::RateLimitError, wait: :polynomially_longer, attempts: 3

  # household_id: re-price one household (enqueued after that household's
  # Coinbase/Alchemy sync). nil: the recurring sweep over every household.
  sig { params(household_id: T.nilable(String)).void }
  def perform(household_id = nil)
    # Crypto balances and watchlists are per household, and each household
    # brings its own CoinMarketCap key — sync each in its own context.
    scope = household_id ? Household.where(id: household_id) : Household.all
    each_household(scope: scope, reraise: [ CoinMarketCap::RateLimitError ]) do |household|
      next unless CoinMarketCap.configured?

      sync(household)
    end
  end

  private

  sig { params(household: Household).void }
  def sync(household)
    result = CoinMarketCap::Syncer.new.call
    Rails.logger.info("[SyncCryptoPricesJob] household=#{household.id} updated=#{result.updated} skipped=#{result.skipped} errors=#{result.errors.size}")
    result.errors.each { |e| Rails.logger.error("[SyncCryptoPricesJob] #{e[:account]}: #{e[:error]}") }
    Activity.record(
      source: "crypto_prices", event: "sync.completed",
      severity: result.errors.any? ? Severity::Warning : Severity::Info,
      summary: "Crypto price sync: #{result.updated} updated, #{result.skipped} skipped" \
               "#{result.errors.any? ? ", #{result.errors.size} errors" : ''}",
      payload: { updated: result.updated, skipped: result.skipped, errors: result.errors.size }
    )
  rescue CoinMarketCap::RateLimitError
    raise
  rescue => e
    # One household's bad key or data must not abort every household
    # after it — record and move on.
    Rails.logger.error("[SyncCryptoPricesJob] household=#{household.id} #{e.class}: #{e.message}")
    Activity.record(
      source: "crypto_prices", event: "sync.failed", severity: Severity::Error,
      summary: "Crypto price sync failed: #{e.class}: #{e.message}",
      payload: { error_class: e.class.name }
    )
  end
end
