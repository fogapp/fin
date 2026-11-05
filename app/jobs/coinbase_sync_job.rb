# typed: true

class CoinbaseSyncJob < ApplicationJob
  extend T::Sig

  queue_as :default
  limits_concurrency to: 1, key: ->(household_id) { household_id }

  sig { params(household_id: String).void }
  def perform(household_id)
    with_household(household_id) do |household|
      next unless Coinbase.configured?

      result = CoinbaseSyncer.new.call
      Rails.logger.info(
        "[CoinbaseSyncJob] household=#{household_id} " \
        "added=#{result.added} skipped=#{result.skipped} errors=#{result.errors.length}"
      )
      result.errors.each { |e| Rails.logger.warn("[CoinbaseSyncJob] #{e.inspect}") }
      Workflows::Events.publish("coinbase.sync_completed", subject: household,
                                payload: { "added" => result.added, "skipped" => result.skipped,
                                           "errors" => result.errors.length })
      Activity.record(
        source: "coinbase_sync", event: "sync.completed",
        severity: result.errors.any? ? Severity::Warning : Severity::Info,
        summary: "Coinbase sync: #{result.added} added, #{result.skipped} skipped" \
                 "#{result.errors.any? ? ", #{result.errors.length} errors" : ''}",
        payload: { added: result.added, skipped: result.skipped, errors: result.errors.length }
      )

      SyncCryptoPricesJob.perform_later(household_id) if CoinMarketCap.configured?
    end
  end
end
