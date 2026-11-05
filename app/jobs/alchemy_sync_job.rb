# typed: true

class AlchemySyncJob < ApplicationJob
  extend T::Sig

  queue_as :default
  limits_concurrency to: 1, key: ->(household_id) { household_id }

  sig { params(household_id: String).void }
  def perform(household_id)
    with_household(household_id) do |household|
      next unless AlchemyConfiguration.current.configured?

      result = AlchemySyncer.new.call
      Rails.logger.info(
        "[AlchemySyncJob] household=#{household_id} " \
        "wallets=#{result.wallets} positions=#{result.positions} errors=#{result.errors.length}"
      )
      result.errors.each { |e| Rails.logger.warn("[AlchemySyncJob] #{e.inspect}") }
      Workflows::Events.publish("alchemy.sync_completed", subject: household,
                                payload: { "wallets" => result.wallets, "positions" => result.positions,
                                           "errors" => result.errors.length })

      # With fresh observations in hand, absorb gas-sized native-token drift
      # so reconciliation stays quiet (gas isn't tracked per transaction).
      if AlchemyConfiguration.current.transactions_configured?
        sweep = Alchemy::GasDriftSweep.new.call
        Rails.logger.info("[AlchemySyncJob] gas sweep swept=#{sweep.swept} skipped=#{sweep.skipped}")
      end

      SyncCryptoPricesJob.perform_later(household_id) if CoinMarketCap.configured?
    end
  end
end
