# typed: true

module MarketData
  # Daily FX rates for every non-USD fiat currency seen on accounts, so
  # foreign balances convert honestly instead of being summed as USD.
  class FxSyncJob < ApplicationJob
    extend T::Sig

    queue_as :market_data
    limits_concurrency to: 1, key: -> { "fx_sync" }

    sig { void }
    def perform
      currencies = Account.unscoped
        .where.not(account_type: "crypto")
        .where.not(balance_currency: [ nil, "USD" ])
        .distinct.pluck(:balance_currency)
      return if currencies.empty?

      client = AlphaVantage::Client.new
      synced = 0
      currencies.each do |currency|
        rate = client.fx_rate(currency, "USD")
        next if rate.nil?

        FxRate.upsert(
          { base: currency, quote: "USD", date: Date.current, rate: rate,
            source: "alpha_vantage", created_at: Time.current, updated_at: Time.current },
          unique_by: %i[base quote date]
        )
        synced += 1
      rescue AlphaVantage::RateLimitError
        # Provider-wide: the remaining currencies would hit the same wall.
        # Re-raise so ApplicationJob's baseline retry runs the (idempotent)
        # job again with backoff instead of logging "synced 0/N" as success.
        raise
      rescue AlphaVantage::Error => e
        Rails.logger.warn("[FxSyncJob] #{currency}: #{e.message}")
      end
      Rails.logger.info("[FxSyncJob] synced #{synced}/#{currencies.size} currencies")
    end
  end
end
