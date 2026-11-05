# typed: strict

require "openssl"
require "base64"
require "json"
require "securerandom"

class CoinbaseClient
  extend T::Sig

  # Surfaced verbatim to callers (e.g. POST /coinbase/configuration/test); the
  # controller relies on this class to decide what's safe to relay to the client.
  class Error < StandardError; end

  BASE_URL = T.let("https://api.coinbase.com".freeze, String)

  sig { void }
  def initialize
    creds = Coinbase.credentials
    raise ArgumentError, "Coinbase credentials not configured" unless creds

    @key_id     = T.let(creds.key_id, String)
    @key_secret = T.let(creds.key_secret, String)

    # Secret is the base64-encoded libsodium Ed25519 keypair (seed || public, 64 bytes).
    # Extract the 32-byte seed and wrap it in a PKCS#8 DER structure that OpenSSL can load.
    seed      = Base64.decode64(@key_secret)[0, 32]
    pkcs8_der = "\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20".b + T.must(seed)
    pem       = "-----BEGIN PRIVATE KEY-----\n#{Base64.strict_encode64(pkcs8_der)}\n-----END PRIVATE KEY-----"
    @private_key = T.let(OpenSSL::PKey.read(pem), OpenSSL::PKey::PKey)
  end

  sig { params(limit: Integer).returns(T.untyped) }
  def accounts(limit: 250)
    get("#{BASE_URL}/v2/accounts", limit: limit).dig("data") || []
  end

  sig { params(account_id: String, limit: Integer, starting_after: T.nilable(String)).returns(T.untyped) }
  def account_transactions(account_id, limit: 100, starting_after: nil)
    params = { limit: limit, expand: "all" }
    params[:starting_after] = starting_after if starting_after
    get("#{BASE_URL}/v2/accounts/#{account_id}/transactions", **params)
  end

  private

  sig { params(url: T.any(URI::Generic, String), params: T::Enumerable[Object]).returns(T.untyped) }
  def get(url, params = {})
    uri = URI(url)
    uri.query = URI.encode_www_form(params) if params.any?

    jwt = build_jwt("GET", T.must(uri.host), T.must(uri.path))
    HttpJson.request(:get, uri, error: Error, label: "Coinbase", read_timeout: 10,
                                headers: {
                                  "Authorization" => "Bearer #{jwt}",
                                  "Content-Type"  => "application/json",
                                  "CB-VERSION"    => "2024-01-01"
                                },
                                detail: ->(response) { response.json_object.values_at("error", "message").compact.first })
  end

  # EdDSA JWT for the Coinbase API (Secret API Key / server-to-server).
  # kid and sub = UUID key ID; iss = "cdp"; aud = ["cdp_service"].
  sig { params(method: String, host: String, path: String).returns(String) }
  def build_jwt(method, host, path)
    t = Time.now.to_i
    header  = { "alg" => "EdDSA", "kid" => @key_id, "nonce" => SecureRandom.hex(16) }
    payload = {
      "sub" => @key_id,
      "iss" => "cdp",
      "aud" => [ "cdp_service" ],
      "nbf" => t,
      "exp" => t + 120,
      "uri" => "#{method} #{host}#{path}"
    }

    h    = Base64.urlsafe_encode64(JSON.generate(header),  padding: false)
    p    = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
    data = "#{h}.#{p}"
    sig  = Base64.urlsafe_encode64(@private_key.sign(nil, data), padding: false)
    "#{data}.#{sig}"
  end
end
