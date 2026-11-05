# typed: strict

module Alchemy
  # Which background jobs a change to the household's Alchemy setup should
  # kick off. The settings and wallet endpoints each used to carry their
  # own copy of these rules, with slightly different conditions.
  #
  #   AlchemySyncJob         — balances; needs an API key and a wallet.
  #   TransactionSyncJob     — first-sight sync pins cursors and fans out
  #                            history backfills; needs transaction sync on.
  #   WebhookSyncJob         — reconciles webhook address lists; a cheap
  #                            no-op when real-time is off, so it runs on
  #                            every change while configured.
  class Orchestrator
    extend T::Sig

    sig { params(household_id: String).void }
    def initialize(household_id)
      @household_id = T.let(household_id, String)
    end

    # After settings are saved. `was_configured` / `was_txn_enabled` are
    # read before the save, so first-time setup triggers the initial syncs.
    sig { params(config: AlchemyConfiguration, was_configured: T::Boolean, was_txn_enabled: T::Boolean).void }
    def configuration_changed(config, was_configured:, was_txn_enabled:)
      if !was_configured && config.configured? && AlchemyWallet.active.exists?
        AlchemySyncJob.perform_later(@household_id)
      end
      TransactionSyncJob.perform_later(@household_id) if config.transactions_configured? && !was_txn_enabled
      WebhookSyncJob.perform_later(@household_id) if config.configured?
    end

    sig { params(config: AlchemyConfiguration).void }
    def wallet_added(config)
      AlchemySyncJob.perform_later(@household_id) if config.configured?
      TransactionSyncJob.perform_later(@household_id) if config.transactions_configured?
      WebhookSyncJob.perform_later(@household_id) if config.configured?
    end

    # An edit or removal changes which addresses the webhooks watch.
    sig { params(config: AlchemyConfiguration).void }
    def wallet_changed(config)
      WebhookSyncJob.perform_later(@household_id) if config.configured?
    end
  end
end
