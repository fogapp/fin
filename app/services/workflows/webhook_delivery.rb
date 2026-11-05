# typed: strict

module Workflows
  # Guard-railed outbound HTTP for workflow webhook actions: https only,
  # short timeouts, no redirects followed, response bodies never interpreted.
  module WebhookDelivery
    extend T::Sig

    class Error < StandardError; end

    TIMEOUT_SECONDS = T.let(5, Integer)

    sig { params(url: String, payload: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def self.post(url, payload)
      uri = URI.parse(url)
      raise ArgumentError, "webhook URLs must be https" unless uri.is_a?(URI::HTTPS)

      response = HttpJson.perform(:post, uri, error: Error, label: "Webhook",
                                              headers: { "Content-Type" => "application/json" }, body: payload,
                                              open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS)
      code = response.code.to_i
      { status: code.between?(200, 299) ? "delivered" : "rejected", code: code }
    end
  end
end
