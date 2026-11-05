# typed: true

# Bearer-token authentication shared by the REST API (Api::V1::BaseController)
# and the MCP endpoint (McpController). Looks up the SHA-256 digest of the
# presented token and populates Current with the token's user and household —
# which is what drives the HouseholdScoped default scopes everywhere below.
module ApiTokenAuthentication
  extend ActiveSupport::Concern
  extend T::Helpers

  # Both includers (Api::V1::BaseController and McpController) descend from
  # ActionController::API; declaring it lets Sorbet resolve `request` and
  # `render` here instead of reporting them undefined on the bare module.
  requires_ancestor { ActionController::API }

  private

  def authenticate_with_token!
    token_value = bearer_token
    return render_unauthorized("Missing token") if token_value.blank?

    @api_token = ApiToken.includes(:user, :household).find_by(
      token_digest: Digest::SHA256.hexdigest(token_value)
    )
    return render_unauthorized("Invalid token") if @api_token.nil?
    return render_unauthorized("Token expired") if @api_token.expired?
    return render_read_only_token if @api_token.read_only? && !read_only_request?

    Current.api_token = @api_token
    Current.user      = @api_token.user
    Current.household = @api_token.household

    @api_token.touch_last_used!
  end

  def bearer_token
    header = request.headers["Authorization"]
    header&.start_with?("Bearer ") ? header.delete_prefix("Bearer ") : nil
  end

  # Whether this request only reads, which is all a read-scoped token may
  # do. HTTP's safe methods; a controller whose every call reads (McpController,
  # whose tools are all read-only) overrides it to say so.
  def read_only_request?
    request.get? || request.head?
  end

  def render_unauthorized(message = "Unauthorized")
    render json: { error: message }, status: :unauthorized
  end

  def render_read_only_token
    message = "This token can only read Fin, not change it."
    render json: { error: message, errors: [ message ] }, status: :forbidden
  end
end
