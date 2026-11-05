# typed: true

module Alchemy
  # Turns a webhook delivery into a targeted incremental poll: match the
  # activity's addresses against the household's wallets and enqueue the
  # transaction sync narrowed to them. The sync job's per-household
  # concurrency limit debounces delivery bursts.
  class WebhookEventJob < ApplicationJob
    extend T::Sig

    queue_as :default

    sig { params(webhook_id: String, payload: T::Hash[String, T.untyped]).void }
    def perform(webhook_id, payload)
      with_record(AlchemyWebhook, webhook_id) do |webhook|
        next unless AlchemyConfiguration.current.transactions_configured?

        activity  = Array(payload.dig("event", "activity"))
        addresses = activity.flat_map { |a| [ a["fromAddress"], a["toAddress"] ] }
                            .compact.map(&:downcase).uniq
        wallet_ids = AlchemyWallet.active.where(address: addresses).pluck(:id)
        next if wallet_ids.empty?

        TransactionSyncJob.perform_later(webhook.household_id, wallet_ids: wallet_ids)
      end
    end
  end
end
