# typed: strict

module Alchemy
  # Alchemy's three APIs explain failures in different places: the node
  # (JSON-RPC) and Portfolio APIs under error.message, the Notify API in a
  # top-level message. The explanation is what makes most of these errors
  # fixable (e.g. "ETH_MAINNET is not enabled for this app"), so every
  # client surfaces it.
  module ErrorMessage
    extend T::Sig

    sig { params(response: HttpJson::Response).returns(T.nilable(String)) }
    def self.from(response)
      body  = response.json_object
      error = body["error"]
      message = error.is_a?(Hash) ? error["message"] : error
      (message.presence || body["message"].presence)&.to_s
    end
  end
end
