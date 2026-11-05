# typed: strict

module Alchemy
  # Client for Alchemy's Notify (dashboard) API, which manages webhooks.
  # Authenticates with the household's auth token (X-Alchemy-Token) — a
  # separate credential from the node/portfolio api_key.
  class NotifyClient
    extend T::Sig

    class Error < StandardError; end

    BASE_URL = T.let("https://dashboard.alchemy.com/api".freeze, String)

    sig { params(auth_token: T.nilable(String)).void }
    def initialize(auth_token: nil)
      token = auth_token.presence || AlchemyConfiguration.current.auth_token.presence
      raise ArgumentError, "Alchemy auth token not configured" if token.blank?

      @auth_token = T.let(token, String)
    end

    # => { external_id:, signing_key: }
    sig { params(network: String, url: String, addresses: T::Array[String]).returns(T::Hash[Symbol, String]) }
    def create_address_activity_webhook(network:, url:, addresses:)
      data = request(:post, "create-webhook",
                     network:      Networks.to_webhook(network),
                     webhook_type: "ADDRESS_ACTIVITY",
                     webhook_url:  url,
                     addresses:    addresses).fetch("data", {})
      { external_id: data["id"].to_s, signing_key: data["signing_key"].to_s }
    end

    sig { params(external_id: String, add: T::Array[String], remove: T::Array[String]).void }
    def update_webhook_addresses(external_id:, add: [], remove: [])
      return if add.empty? && remove.empty?

      request(:patch, "update-webhook-addresses",
              webhook_id:           external_id,
              addresses_to_add:     add,
              addresses_to_remove:  remove)
      nil
    end

    sig { params(external_id: String).void }
    def delete_webhook(external_id:)
      request(:delete, "delete-webhook", webhook_id: external_id)
      nil
    rescue Error => e
      # Deleting a webhook that's already gone should not fail the reconcile.
      raise unless e.message.include?("404")
    end

    sig { returns(T::Array[T.untyped]) }
    def team_webhooks
      Array(request(:get, "team-webhooks").fetch("data", []))
    end

    private

    sig { params(method: Symbol, path: String, body: T.untyped).returns(T.untyped) }
    def request(method, path, body = nil)
      HttpJson.request(method, URI("#{BASE_URL}/#{path}"),
                       error: Error, label: "Alchemy Notify", read_timeout: 30, allow_empty: true,
                       body: method == :get ? nil : body,
                       headers: {
                         "X-Alchemy-Token" => @auth_token,
                         "Content-Type"    => "application/json",
                         "Accept"          => "application/json"
                       },
                       detail: ->(response) { Alchemy::ErrorMessage.from(response) })
    end
  end
end
