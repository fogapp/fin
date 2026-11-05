# typed: strict

# fog's household event stream (fog:docs/events-contract.md): Fin says what
# happened — a notification, a workflow's event — and whoever reads the
# stream (HUD) decides what it deserves. Authenticated by the FOG_API_TOKEN
# fog injects into every app, so there is nothing to configure; off fog the
# variables are absent and there is no client.
#
# Not Workflows::WebhookDelivery: that guards URLs a user typed (https only).
# FOG_API_URL is fogd on the host at the address fog itself injected — plain
# http to a private address by design, never one handed to Fin by content.
class FogEventsClient
  extend T::Sig

  class Error < StandardError; end

  # An event is a nicety on top of the durable in-app row, like an ntfy push.
  TIMEOUT_SECONDS = T.let(3, Integer)

  sig { returns(T.nilable(FogEventsClient)) }
  def self.from_env
    url = ENV["FOG_API_URL"].presence
    token = ENV["FOG_API_TOKEN"].presence
    return nil if url.nil? || token.nil?

    new(base_url: url, token: token)
  end

  sig { params(base_url: String, token: String).void }
  def initialize(base_url:, token:)
    @base_url = T.let(base_url.chomp("/"), String)
    @token = token
  end

  # One CloudEvent. fog sets the source to this app; a retry with the same
  # id is absorbed there, so ids name the occurrence.
  sig { params(type: String, id: String, subject: String, data: T::Hash[String, T.untyped]).void }
  def publish(type:, id:, subject:, data:)
    response = HttpJson.perform(:post, URI("#{@base_url}/app/v1/events"), error: Error, label: "fog events",
                                headers: { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" },
                                body: { specversion: "1.0", id: id, type: type, subject: subject.truncate(256),
                                        time: Time.now.utc.iso8601, data: data },
                                open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS)
    return if response.code == "202"

    Lucid.increment("upstream.failures", tags: { upstream: "fog events", reason: response.code })
    raise Error, "fog answered #{response.code} to an event"
  end
end
