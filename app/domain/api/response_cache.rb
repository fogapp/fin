# typed: strict

module Api
  # Shared read-through cache for the heavy JSON renderers, used by both the
  # REST controllers (BaseController#render_cached, which adds the ETag layer)
  # and the MCP tools (Mcp::Tools::Base#cached_json_response). Both build the
  # key here, so an MCP call and the equivalent REST request hit the same
  # entry instead of each recomputing — and the key recipe can't drift
  # between the two.
  #
  # Keys embed the household's DataVersion, so any committed financial write
  # invalidates by key rotation, and CODE_VERSION, so a deploy that changes a
  # payload shape does too; the TTL bounds staleness from writes that bypass
  # callbacks (upsert_all imports, market-price syncs). The key also carries
  # the time zone the request runs in (the instance setting), since payloads
  # bucket by local day. Only the whitelisted params enter the key, so a
  # stray query param can't fork extra entries.
  module ResponseCache
    # DataVersion tracks the *data*; payload shapes change with the *code*.
    # Without a code component in the cache key, a client holding a
    # pre-deploy ETag keeps getting 304s and replays a body that predates
    # the new fields — a browser can sit on the old shape indefinitely,
    # since nothing but a household write ever rotates the key. In
    # development the sha doesn't move on every edit, but this module is
    # reloaded when it does, so boot time stands in.
    CODE_VERSION = T.let(
      (Rails.env.development? ? Process.clock_gettime(Process::CLOCK_REALTIME).to_i.to_s : ENV["GIT_SHA"].to_s).freeze,
      String
    )

    class << self
      extend T::Sig

      # The cache key (and, for REST, the strong ETag) for `name` given the
      # caller's raw values. `values` may use string or symbol keys; only the
      # `params` whitelist is read. REST query values arrive as strings (or
      # arrays of strings for `ids[]=`); MCP arguments may be any JSON scalar,
      # so scalars are stringified to match what the same value would look
      # like as a query param.
      sig { params(name: String, values: T::Hash[T.untyped, T.untyped], params: T::Array[T.any(Symbol, String)]).returns(T::Array[T.untyped]) }
      def key(name, values, params:)
        household_id = Current.household.id
        whitelisted = params.filter_map { |param|
          value = values[param.to_s]
          value = values[param.to_sym] if value.nil?
          [ param.to_s, normalize(value) ] unless value.nil?
        }.sort
        [ "api", name, household_id, Households::DataVersion.current(household_id), CODE_VERSION, Time.zone.tzinfo.name, whitelisted ]
      end

      # Fetches the encoded JSON string for `key`, computing it from the
      # block on a miss. The payload is stored already encoded: hits hand it
      # back verbatim instead of paying a Marshal load plus a JSON re-encode.
      # race_condition_ttl: when an entry expires under concurrent traffic,
      # one worker recomputes while the rest briefly serve the stale value,
      # instead of a recompute stampede.
      sig { params(key: T::Array[T.untyped], expires_in: ActiveSupport::Duration, block: T.proc.returns(T.untyped)).returns(String) }
      def fetch_json(key, expires_in: 5.minutes, &block)
        Rails.cache.fetch(key, expires_in: expires_in, race_condition_ttl: 10.seconds) do
          ActiveSupport::JSON.encode(block.call)
        end
      end

      private

      sig { params(value: T.untyped).returns(T.untyped) }
      def normalize(value)
        case value
        when String, Hash then value
        when Array then value.map { |v| normalize(v) }
        else value.to_s
        end
      end
    end
  end
end
