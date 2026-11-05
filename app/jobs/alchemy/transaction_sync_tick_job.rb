# typed: true

module Alchemy
  # Runs every 5 minutes and enqueues the household transaction sync when its
  # configured frequency says it's due. One recurring entry; frequency
  # changes in the UI take effect without a deploy.
  class TransactionSyncTickJob < ApplicationJob
    extend T::Sig

    queue_as :default

    sig { void }
    def perform
      each_household do |household|
        config = AlchemyConfiguration.current
        next unless config.transactions_configured? && config.poll_due?

        TransactionSyncJob.perform_later(household.id)
      end
    end
  end
end
