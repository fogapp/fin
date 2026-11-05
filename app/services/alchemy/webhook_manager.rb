# typed: strict

module Alchemy
  # Declarative reconcile between the household's desired webhook state
  # (real-time transactions enabled + credentials present → one Address
  # Activity webhook per network with all active wallet addresses) and what
  # exists, both in Alchemy and in our alchemy_webhooks rows. Idempotent;
  # per-network failures mark the row and continue.
  class WebhookManager
    extend T::Sig

    sig { returns(T::Array[AlchemyWebhook]) }
    def sync!
      config = AlchemyConfiguration.current

      desired = desired_networks(config)
      existing = AlchemyWebhook.all.index_by(&:network)

      # Tear down networks that should no longer have a webhook.
      existing.each do |network, webhook|
        next if desired.key?(network)

        delete_webhook(webhook)
      end

      desired.map do |network, addresses|
        reconcile_network(config, network, addresses, existing[network])
      end.compact
    end

    private

    # {network => [addresses]} — empty when webhooks shouldn't exist at all.
    sig { params(config: AlchemyConfiguration).returns(T::Hash[String, T::Array[String]]) }
    def desired_networks(config)
      return {} unless config.transactions_configured? && config.realtime?
      return {} if config.auth_token.blank? || config.webhook_base_url.blank?

      AlchemyWallet.active.flat_map { |w| w.networks.map { |n| [ n, w.address ] } }
                   .group_by(&:first)
                   .transform_values { |pairs| pairs.map(&:last).uniq.sort }
    end

    sig do
      params(config: AlchemyConfiguration, network: String, addresses: T::Array[String],
             webhook: T.nilable(AlchemyWebhook)).returns(T.nilable(AlchemyWebhook))
    end
    def reconcile_network(config, network, addresses, webhook)
      url = webhook_url(config)

      # Alchemy has no "change this webhook's URL" — a webhook registered for
      # another address (the base URL was edited, or the instance moved) is
      # replaced, or it would keep delivering to where Fin used to be.
      if webhook && webhook.url != url
        client.delete_webhook(external_id: webhook.external_id)
        webhook.destroy!
        webhook = nil
      end

      if webhook.nil?
        created = client.create_address_activity_webhook(network: network, url: url, addresses: addresses)
        return AlchemyWebhook.create!(
          household_id: Current.household.id,
          network:      network,
          external_id:  created.fetch(:external_id),
          signing_key:  created[:signing_key],
          url:          url,
          status:       AlchemyWebhook::Status::Active
        )
      end

      current = tracked_addresses(webhook)
      client.update_webhook_addresses(
        external_id: webhook.external_id,
        add:         addresses - current,
        remove:      current - addresses
      )
      webhook.update!(status: AlchemyWebhook::Status::Active, url: url, last_error: nil)
      webhook
    rescue NotifyClient::Error, ArgumentError => e
      webhook&.update!(status: AlchemyWebhook::Status::Error, last_error: e.message.truncate(255))
      nil
    end

    sig { params(webhook: AlchemyWebhook).void }
    def delete_webhook(webhook)
      client.delete_webhook(external_id: webhook.external_id)
      webhook.destroy!
    rescue NotifyClient::Error => e
      webhook.update!(status: AlchemyWebhook::Status::Error, last_error: e.message.truncate(255))
    end

    # Alchemy's team-webhooks listing carries the current address set; fall
    # back to "unknown → resend everything" (adds are idempotent).
    sig { params(webhook: AlchemyWebhook).returns(T::Array[String]) }
    def tracked_addresses(webhook)
      remote = client.team_webhooks.find { |w| w["id"] == webhook.external_id }
      Array(remote&.fetch("addresses", nil)).map(&:downcase)
    rescue NotifyClient::Error
      []
    end

    sig { params(config: AlchemyConfiguration).returns(String) }
    def webhook_url(config)
      base = T.must(config.webhook_base_url).chomp("/")
      "#{base}/webhooks/alchemy"
    end

    # T.untyped so instance doubles pass the runtime sig in specs.
    sig { returns(T.untyped) }
    def client
      @client = T.let(@client, T.untyped)
      @client ||= NotifyClient.new
    end
  end
end
