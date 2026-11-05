# typed: strict

# Credential resolution for the Coinbase integration, shared by CoinbaseClient
# and every "should we sync?" check so they can't disagree: the current
# household's CoinbaseConfiguration first, then ENV (deploys that predate the
# Settings → Integrations entry).
module Coinbase
  extend T::Sig

  Credentials = Struct.new(:key_id, :key_secret, keyword_init: true)

  sig { returns(T.nilable(Credentials)) }
  def self.credentials
    config     = CoinbaseConfiguration.current
    key_id     = config.api_key_id.presence     || ENV["COINBASE_API_KEY_ID"].presence
    key_secret = config.api_key_secret.presence || ENV["COINBASE_API_KEY_SECRET"].presence
    return nil unless key_id && key_secret

    Credentials.new(key_id: key_id, key_secret: key_secret)
  end

  sig { returns(T::Boolean) }
  def self.configured?
    !credentials.nil?
  end
end
