# typed: strict
# frozen_string_literal: true

# The one auth rule of every fog contract surface (backup, integrations):
# fog presents FOG_API_TOKEN, the per-app shared secret it injects at
# deploy, as a bearer token. Deliberately outside the API token stack, so the
# surface works on a fresh instance with zero users (a restore needs it
# then) and dodges the household default scope. No token configured means
# the surface doesn't exist. Each includer declares the before_action, as
# with ApiTokenAuthentication.
module FogContractAuth
  extend ActiveSupport::Concern
  extend T::Sig

  extend T::Helpers

  requires_ancestor { ActionController::API }

  private

  # Constant-time compare against the fog-injected token.
  sig { void }
  def authenticate_fog!
    expected = ENV["FOG_API_TOKEN"].presence
    presented = fog_bearer_token
    if expected.nil? || presented.nil? ||
        !ActiveSupport::SecurityUtils.secure_compare(expected, presented)
      render json: { errors: [ "unauthorized" ] }, status: :unauthorized
    end
  end

  sig { returns(T.nilable(String)) }
  def fog_bearer_token
    header = request.headers["Authorization"].to_s
    return header.split(" ", 2).last if header.start_with?("Bearer ")

    nil
  end

  # Errors are {"errors": [...]}: fog shows the first to the operator as
  # written, so each is a sentence they can act on.
  sig { params(message: String, status: Symbol).void }
  def render_fog_errors(message, status:)
    render json: { errors: [ message ] }, status: status
  end
end
