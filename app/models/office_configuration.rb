# typed: true

# Credentials for the household's Office instance. Office is a sibling
# self-hosted app (a document editor with spreadsheets); Fin talks to it
# over its MCP endpoint with a bearer API token minted there.
#
# Unlike the market-data providers, this integration has no settings UI —
# the row is set from a console, or left absent so the ENV fallbacks below
# supply the connection.
class OfficeConfiguration < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include HouseholdConfiguration

  encrypts :api_key

  validate :base_url_is_http

  # The row's value, else the deployment-wide fallback. A household that
  # never saves a row still reaches the Office instance the container was
  # pointed at.
  sig { returns(T.nilable(String)) }
  def resolved_base_url
    (base_url.presence || ENV["OFFICE_URL"].presence)&.sub(%r{/+\z}, "")
  end

  sig { returns(T.nilable(String)) }
  def resolved_api_key
    api_key.presence || ENV["OFFICE_API_TOKEN"].presence
  end

  sig { returns(T::Boolean) }
  def configured?
    resolved_base_url.present? && resolved_api_key.present?
  end

  private

  # A base URL that isn't http(s) would have Net::HTTP raise deep inside a
  # request; catching it here keeps the failure on the write that caused it.
  sig { void }
  def base_url_is_http
    return if base_url.blank?

    uri = URI.parse(base_url)
    errors.add(:base_url, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:base_url, "is not a valid URL")
  end
end
