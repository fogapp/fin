# typed: true

module Alchemy
  # Runs the incremental on-chain transaction sync for one household,
  # optionally narrowed to specific wallets (webhook hints pass wallet_ids).
  # The per-household concurrency limit also debounces webhook bursts: ten
  # deliveries in a minute collapse into serialized runs whose later ones
  # find nothing new.
  class TransactionSyncJob < ApplicationJob
    extend T::Sig

    queue_as :default
    limits_concurrency to: 1, key: ->(household_id, **) { "alchemy_tx:#{household_id}" }

    sig { params(household_id: String, wallet_ids: T.nilable(T::Array[String])).void }
    def perform(household_id, wallet_ids: nil)
      with_household(household_id) do |household|
        config = AlchemyConfiguration.current
        next unless config.transactions_configured?

        # Stamp at start so the frequency tick can't double-fire mid-run.
        config.update_columns(transactions_last_synced_at: Time.current) if config.persisted?

        wallets = AlchemyWallet.active
        wallets = wallets.where(id: wallet_ids) if wallet_ids.present?
        result  = TransactionSyncer.new.call(wallets: wallets)

        Rails.logger.info(
          "[Alchemy::TransactionSyncJob] household=#{household_id} pairs=#{result.pairs} " \
          "new_transfers=#{result.new_transfers} errors=#{result.errors.length}"
        )
        result.errors.each { |e| Rails.logger.warn("[Alchemy::TransactionSyncJob] #{e.inspect}") }

        if result.new_transfers.positive?
          # Balances move with the transactions they explain.
          AlchemySyncJob.perform_later(household_id)
          Workflows::Events.publish("alchemy.transactions_synced", subject: household,
                                    payload: { "new_transfers" => result.new_transfers,
                                               "pairs" => result.pairs,
                                               "errors" => result.errors.length })
        end
      end
    end
  end
end
