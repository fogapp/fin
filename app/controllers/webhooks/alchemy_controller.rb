# typed: true

module Webhooks
  # Inbound Alchemy Address Activity deliveries. Deliberately outside
  # Api::V1::BaseController: there is no bearer token on a webhook request —
  # authentication is the HMAC-SHA256 of the raw body with the per-webhook
  # signing key (X-Alchemy-Signature). Responds fast and defers all work.
  class AlchemyController < ActionController::API
    extend T::Sig

    def create
      raw     = request.raw_post
      payload = parse(raw)
      return head :bad_request if payload.nil? || payload["webhookId"].blank?

      webhook = AlchemyWebhook.unscoped.find_by(external_id: payload["webhookId"])
      return head :not_found unless webhook

      unless valid_signature?(webhook, raw)
        Current.set(household: webhook.household) do
          Activity.record(
            source: "alchemy_webhook", event: "webhook.rejected", severity: Severity::Warning,
            summary: "Rejected Alchemy webhook delivery for #{webhook.network}: bad signature",
            payload: { webhook_id: webhook.external_id, network: webhook.network }
          )
        end
        return head :unauthorized
      end

      webhook.update_columns(last_received_at: Time.current, status: "active", last_error: nil)
      # Hint, not ingest: the delivery only tells us which addresses moved.
      # The delayed poll (past confirmation depth) is the single ingestion
      # path, so missed/duplicate/out-of-order deliveries cost nothing.
      Alchemy::WebhookEventJob.set(wait: 90.seconds)
        .perform_later(webhook.id, payload.slice("event"))
      head :ok
    end

    private

    sig { params(raw: String).returns(T.nilable(T::Hash[String, T.untyped])) }
    def parse(raw)
      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    sig { params(webhook: AlchemyWebhook, raw: String).returns(T::Boolean) }
    def valid_signature?(webhook, raw)
      key = webhook.signing_key.to_s
      return false if key.blank?

      signature = request.headers["X-Alchemy-Signature"].to_s
      expected  = OpenSSL::HMAC.hexdigest("SHA256", key, raw)
      signature.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.fixed_length_secure_compare(signature, expected)
    end
  end
end
