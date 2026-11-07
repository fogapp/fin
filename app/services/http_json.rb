# typed: strict

require "net/http"
require "json"
require "openssl"

# Shared transport for the hand-rolled API clients (market data, crypto,
# Alchemy, RentCast, Office, workflow webhooks). Each client keeps its own
# public API and error classes; this owns the parts they used to copy with
# small drift between them:
#
# - Timeouts are always explicit (a dead host must not hold a job thread
#   for Net::HTTP's implicit 60s).
# - Status is checked before the body is parsed. Rate-limit and gateway
#   errors often arrive with an HTML body, and a JSON::ParserError there
#   used to bypass the caller's rate-limit handling entirely.
# - Network failures (timeouts, DNS, refused connections, TLS) surface as
#   the client's own error class, so callers that rescue `Client::Error`
#   see them instead of a raw Net:: exception slipping past.
#
# `perform` is the transport alone (for clients with bespoke status
# handling); `request` adds the common status → error mapping and JSON
# parsing on top.
module HttpJson
  extend T::Sig

  NETWORK_ERRORS = T.let([
    Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, EOFError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
    OpenSSL::SSL::SSLError
  ].freeze, T::Array[T.class_of(Exception)])

  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 15

  REQUEST_CLASSES = T.let({
    get:    Net::HTTP::Get,
    post:   Net::HTTP::Post,
    patch:  Net::HTTP::Patch,
    put:    Net::HTTP::Put,
    delete: Net::HTTP::Delete
  }.freeze, T::Hash[Symbol, T.class_of(Net::HTTPRequest)])

  class Response < T::Struct
    extend T::Sig

    const :raw, Net::HTTPResponse

    sig { returns(String) }
    def code = raw.code.to_s

    sig { returns(String) }
    def body = raw.body.to_s

    sig { returns(T::Boolean) }
    def success? = raw.is_a?(Net::HTTPSuccess)

    # The parsed body, or nil when it is empty or not JSON.
    sig { returns(T.untyped) }
    def json
      body.blank? ? nil : JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    # The parsed body when it is a JSON object, else {} — for digging an
    # error message out of a body that may be anything.
    sig { returns(T::Hash[String, T.untyped]) }
    def json_object
      parsed = json
      parsed.is_a?(Hash) ? parsed : {}
    end
  end

  # Sends one request and returns the response whatever its status.
  # `body` is sent as-is when a String, else JSON-encoded.
  sig do
    params(
      method: Symbol, uri: URI::Generic,
      error: T.class_of(StandardError), label: String,
      headers: T::Hash[String, String], body: T.untyped,
      open_timeout: Integer, read_timeout: Integer,
      network_message: T.nilable(T.proc.params(e: Exception).returns(String))
    ).returns(Response)
  end
  def self.perform(method, uri, error:, label:, headers: {}, body: nil,
                   open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
                   network_message: nil)
    request = REQUEST_CLASSES.fetch(method).new(uri)
    headers.each { |name, value| request[name] = value }
    request.body = body.is_a?(String) ? body : body.to_json unless body.nil?

    raw = Net::HTTP.start(T.must(uri.hostname), uri.port, use_ssl: uri.scheme == "https",
                          open_timeout: open_timeout, read_timeout: read_timeout) do |http|
      http.request(request)
    end
    Response.new(raw: raw)
  rescue *NETWORK_ERRORS => e
    Glass.increment("upstream.failures", tags: { upstream: label, reason: "network" })
    raise error, network_message ? network_message.call(e) : "#{label} request failed (#{e.class}): #{e.message}"
  end

  # Sends one request and returns the parsed JSON body. Non-2xx responses
  # raise "#{label} #{code}: #{detail}", where detail comes from `detail`
  # (given the response) or falls back to the start of the body. A 429
  # raises `rate_limit_error` and a 401/403 `auth_error` when given, else
  # `error`. An empty 2xx body returns {} when `allow_empty`.
  sig do
    params(
      method: Symbol, uri: URI::Generic,
      error: T.class_of(StandardError), label: String,
      headers: T::Hash[String, String], body: T.untyped,
      open_timeout: Integer, read_timeout: Integer,
      rate_limit_error: T.nilable(T.class_of(StandardError)),
      auth_error: T.nilable(T.class_of(StandardError)),
      detail: T.nilable(T.proc.params(response: Response).returns(T.nilable(String))),
      allow_empty: T::Boolean
    ).returns(T.untyped)
  end
  def self.request(method, uri, error:, label:, headers: {}, body: nil,
                   open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
                   rate_limit_error: nil, auth_error: nil, detail: nil, allow_empty: false)
    response = perform(method, uri, error: error, label: label, headers: headers, body: body,
                                    open_timeout: open_timeout, read_timeout: read_timeout)

    unless response.success?
      Glass.increment("upstream.failures", tags: { upstream: label, reason: response.code })
      message = "#{label} #{response.code}: #{detail&.call(response).presence || response.body.strip[0, 200]}"
      raise rate_limit_error, message if rate_limit_error && response.code == "429"
      raise auth_error, message if auth_error && %w[401 403].include?(response.code)

      raise error, message
    end

    return {} if allow_empty && response.body.blank?

    parsed = response.json
    raise error, "#{label} returned a non-JSON response" if parsed.nil?

    parsed
  end
end
