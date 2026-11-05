# typed: strict

# Thin wrapper over the RentCast API (https://api.rentcast.io/v1).
#
# Two endpoints matter here:
#
#   GET /avm/value  — the current AVM estimate, with an 85%-confidence
#                     range. One point in time; RentCast has no
#                     value-history endpoint, which is why we store every
#                     estimate ourselves.
#   GET /properties — the full record: facts, year-keyed taxAssessments,
#                     and date-keyed sale history. One call seeds years of
#                     chart data.
#
# Every request passes through RentcastConfiguration#consume_quota! before
# it leaves the process. The free tier allows 50 requests a month, so the
# counter lives in the client rather than at the call sites — there is no
# way to spend a request without it being counted.
module Rentcast
  class Client
    extend T::Sig

    # Surfaced verbatim to callers (e.g. POST /rentcast/configuration/test);
    # controllers rely on this class to decide what's safe to relay.
    class Error < StandardError; end

    # The address had no match in RentCast's data. Distinct from Error
    # because the caller's response is different: fall back to manual
    # valuation rather than retry.
    class NotFound < Error; end

    BASE_URL = T.let("https://api.rentcast.io/v1".freeze, String)

    sig { params(api_key: T.nilable(String), configuration: T.nilable(RentcastConfiguration)).void }
    def initialize(api_key: nil, configuration: nil)
      @configuration = T.let(configuration || RentcastConfiguration.current, RentcastConfiguration)
      key = api_key.presence || @configuration.api_key.presence || ENV["RENTCAST_API_KEY"]
      raise ArgumentError, "RentCast API key not configured" if key.blank?

      @api_key = T.let(key, String)
    end

    # Current AVM value estimate. Returns the raw hash: price,
    # priceRangeLow, priceRangeHigh, subjectProperty, comparables.
    sig { params(address: String).returns(T::Hash[String, T.untyped]) }
    def value_estimate(address)
      get("avm/value", address: address)
    end

    # Full property record. RentCast returns either an object or a
    # single-element array depending on the query; normalize to a hash.
    sig { params(address: String).returns(T::Hash[String, T.untyped]) }
    def property_record(address)
      body = get("properties", address: address)
      record = body.is_a?(Array) ? body.first : body
      raise NotFound, "RentCast has no property record for #{address}" if record.blank?

      T.cast(record, T::Hash[String, T.untyped])
    end

    # Proves the key is accepted. Costs one request against the monthly
    # allowance.
    #
    # Deliberately a city/state record lookup rather than an address
    # valuation: it exercises exactly the credentials and nothing else, so a
    # failure here means the key, subscription, or billing — never a geocoding
    # miss on whatever address we happened to pick.
    sig { void }
    def test_connection!
      get("properties", city: "Austin", state: "TX", limit: 1)
      nil
    end

    # Percent-encoding, not form-encoding. URI.encode_www_form writes spaces
    # as "+", which RentCast's address parser takes literally — every lookup
    # comes back 400 "could not be parsed or geolocated" even with a valid
    # key. Their own examples use %20.
    sig { params(query: T::Hash[Symbol, T.untyped]).returns(String) }
    def self.build_query(query)
      query.map { |key, value|
        "#{key}=#{URI.encode_www_form_component(value.to_s).gsub('+', '%20')}"
      }.join("&")
    end

    private

    sig { params(path: String, query: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def get(path, query)
      # Reserve before sending: a crash mid-flight must not hand the request
      # back, because RentCast counted it regardless.
      @configuration.consume_quota!

      uri       = URI("#{BASE_URL}/#{path}")
      uri.query = self.class.build_query(query)

      response = HttpJson.perform(:get, uri, error: Error, label: "RentCast", read_timeout: 20,
                                             headers: { "X-Api-Key" => @api_key, "Accept" => "application/json" })
      handle(response, path)
    end

    sig { params(response: HttpJson::Response, path: String).returns(T.untyped) }
    def handle(response, path)
      if response.success?
        parsed = response.json
        raise Error, "RentCast returned a non-JSON response on /#{path}" if parsed.nil?

        return parsed
      end

      # RentCast explains itself in the body ("The provided address '...' could
      # not be parsed or geolocated"). Log it and pass it through — swallowing
      # it turns a fixable request-shape bug into a silent dashboard error.
      detail = response.json_object["message"]
      Rails.logger.warn("[Rentcast] #{response.code} on /#{path}: #{detail.presence || response.body.first(200)}")

      case response.raw
      when Net::HTTPNotFound
        raise NotFound, detail.presence || "RentCast has no data for that address"
      when Net::HTTPUnauthorized, Net::HTTPForbidden
        # 401 also covers an inactive subscription and billing problems, not
        # just a bad key — say so, since the key is usually fine.
        raise Error, "RentCast rejected the request (#{detail.presence || 'check the API key, ' \
                     'your subscription status, and billing on your RentCast dashboard'})"
      when Net::HTTPTooManyRequests
        # The plan's allowance is exhausted upstream even though our local
        # counter still had room — trust RentCast and stop.
        raise RentcastConfiguration::QuotaExceeded, "RentCast rate limit or monthly quota reached"
      else
        raise Error, "RentCast #{response.code} on /#{path}: #{detail.presence || 'request failed'}"
      end
    end
  end
end
