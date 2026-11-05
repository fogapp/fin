# typed: true

# Shared error envelope for the two controllers that call the Plaid API
# inline (items#create, link_tokens#create). Wired as a helper called from
# the action's own rescue rather than rescue_from: the actions must swallow
# *every* error to a 422 with a static fallback, and a rescue_from
# StandardError registered here would also hijack the sibling actions'
# not-found/500 envelopes.
module PlaidErrorHandling
  extend ActiveSupport::Concern
  extend T::Sig

  private

  sig { params(error: StandardError, fallback: String).void }
  def render_plaid_error(error, fallback:)
    Rails.logger.error("[Plaid #{controller_name}##{action_name}] #{error.class}: #{error.message}")
    message = fallback
    if error.is_a?(::PlaidClient::NotConfigured)
      # Our own message, written to be shown; nothing internal in it.
      message = error.message
    elsif error.is_a?(::Plaid::ApiError)
      # Plaid's response body contains `error_message`, which is
      # specifically designed to be surfaced to integrators.
      message = ::Plaid::ErrorInfo.from(error).message || fallback
    end
    # Anything non-Plaid could leak internal hostnames or stack info — only
    # the static fallback goes out.
    render json: { error: message }, status: :unprocessable_content
  end
end
