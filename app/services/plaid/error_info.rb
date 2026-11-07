# typed: strict

module Plaid
  # What a Plaid::ApiError says about itself, parsed once. Plaid puts the
  # useful parts in the JSON response body (error_type, error_code, and an
  # error_message written to be shown to integrators); the syncers, the job
  # and the controllers each used to parse it themselves, with their own
  # copies of the "skip this product" and "don't retry" lists.
  class ErrorInfo
    extend T::Sig

    # A product the item can't serve right now (not ready, not enabled,
    # not consented, over its limit). The rest of the item still syncs.
    SKIPPABLE_PRODUCT_CODES = T.let(%w[
      PRODUCT_NOT_READY INVALID_PRODUCT PRODUCTS_NOT_SUPPORTED ADDITIONAL_CONSENT_REQUIRED INVESTMENTS_LIMIT
    ].freeze, T::Array[String])

    # Errors that need the user to re-link or re-consent; no number of
    # retries fixes them.
    NON_RETRIABLE_TYPES = T.let(%w[ITEM_ERROR INVALID_INPUT].freeze, T::Array[String])
    NON_RETRIABLE_CODES = T.let(%w[
      ITEM_LOGIN_REQUIRED INVALID_ACCESS_TOKEN INVALID_API_KEYS ITEM_NOT_FOUND
      ACCESS_NOT_GRANTED USER_PERMISSION_REVOKED ADDITIONAL_CONSENT_REQUIRED
    ].freeze, T::Array[String])

    RATE_LIMIT_TYPE = "RATE_LIMIT_EXCEEDED"

    sig { params(error: ::Plaid::ApiError).returns(ErrorInfo) }
    def self.from(error)
      body = begin
        JSON.parse(error.response_body.to_s)
      rescue JSON::ParserError
        nil
      end
      new(body.is_a?(Hash) ? body : nil)
    end

    sig { params(body: T.nilable(T::Hash[String, T.untyped])).void }
    def initialize(body)
      @body = body
    end

    # False when the body wasn't a JSON object (a gateway page, a timeout).
    sig { returns(T::Boolean) }
    def parsed? = !@body.nil?

    sig { returns(String) }
    def code = @body&.dig("error_code").to_s

    sig { returns(String) }
    def type = @body&.dig("error_type").to_s

    # Plaid's integrator-facing message, or nil.
    sig { returns(T.nilable(String)) }
    def message = @body&.dig("error_message").presence

    sig { returns(T::Boolean) }
    def consent_problem? = message.to_s.downcase.include?("consent")

    # The product (holdings, investment transactions) can't be fetched for
    # this item right now — skip it rather than failing the item's sync.
    sig { returns(T::Boolean) }
    def skippable_product_error?
      SKIPPABLE_PRODUCT_CODES.include?(code) || type == RATE_LIMIT_TYPE || consent_problem?
    end

    # Worth retrying the job? An unparseable body is assumed transient.
    sig { returns(T::Boolean) }
    def retriable?
      return true unless parsed?

      !(NON_RETRIABLE_TYPES.include?(type) || NON_RETRIABLE_CODES.include?(code) || consent_problem?)
    end
  end
end
