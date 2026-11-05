# typed: true

module Api
  module V1
    class BaseController < ActionController::API
      include ApiTokenAuthentication
      include PeriodParams
      include Paginated
      include Renderable
      include TracesRequest

      before_action :authenticate_with_token!

      rescue_from StandardError, with: :render_internal_error
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable
      rescue_from ActionController::BadRequest, with: :render_bad_request
      # ActionController::ParameterMissing inherits from KeyError, not
      # ActionController::BadRequest — without this rescue, a missing
      # required parameter would surface as 500 via the generic handler.
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      # Several endpoints Date.parse user-supplied date params; a malformed
      # date is the client's error, not a 500.
      rescue_from Date::Error, with: :render_bad_request
      # A lost double-submit race on find_or_initialize_by upsert paths
      # (budget lines/periods, merchants) surfaces as a unique-index
      # violation — that's a conflict with the request that won, not a 500.
      rescue_from ActiveRecord::RecordNotUnique, with: :render_conflict

      # Raised by enum_param when a request param isn't a member of the
      # expected enum — the client sent a value outside the contract, so it
      # gets the same 422 envelope as a failed model validation.
      class InvalidEnumParam < StandardError; end

      rescue_from InvalidEnumParam, with: :render_invalid_enum_param

      private

      # Deserializes params[key] against a T::Enum. Blank → default (which
      # may be nil); an unknown value raises InvalidEnumParam → 422 listing
      # the allowed values, instead of the old pattern of passing raw
      # strings straight into queries.
      def enum_param(enum_class, key, default: nil)
        raw = params[key]
        return default if raw.blank?

        enum_class.try_deserialize(raw.to_s) || raise(
          InvalidEnumParam,
          "#{key} must be one of: #{enum_class.values.map(&:serialize).join(', ')}"
        )
      end

      # The account a write should link to, resolved through the household-
      # scoped Account model rather than mass-assigned: another household's
      # account is a 404, never a stored foreign key. Returns {} when the
      # request doesn't mention the key (leave the link alone) and
      # {account_id: nil} for a blank value (clear it), so callers can merge
      # the result straight into their permitted attributes.
      def account_reference(source = params, key: :account_id)
        return {} unless source.key?(key)

        raw = source[key].presence
        { account_id: raw && ::Account.find(raw.to_s).id }
      end

      def render_invalid_enum_param(exception)
        render json: { error: exception.message, errors: [ exception.message ] },
               status: :unprocessable_content
      end

      # Serves a cacheable read endpoint through Api::ResponseCache (see
      # there for what the key embeds). Only the params the endpoint
      # actually reads (the `params:` whitelist) enter the key.
      #
      # The key doubles as a strong ETag — same household + version + params
      # means a byte-identical body — so a matching If-None-Match returns 304
      # before even reading the cached payload.
      def render_cached(name, params: [], expires_in: 5.minutes, &block)
        key = Api::ResponseCache.key(name, request.query_parameters, params: params)
        return unless stale?(strong_etag: key)

        render json: Api::ResponseCache.fetch_json(key, expires_in: expires_in, &block)
      end

      # The caller's membership in the active household — nil for a token
      # whose membership was since removed. Memoized: the admin gate and the
      # endpoint body often both need it within one request.
      def current_membership
        return @current_membership if defined?(@current_membership)

        @current_membership = Current.user.household_memberships.find_by(household_id: Current.household.id)
      end

      def current_admin?
        current_membership&.admin? || false
      end

      # Halts with a 403 unless the current user administers the active
      # household. Used as a before_action; callers pass a message so each
      # endpoint keeps its specific "Only admins can …" wording.
      def require_household_admin!(message = "Admin access required")
        render json: { error: message }, status: :forbidden unless current_admin?
      end

      # Accepted-for-async envelope: the endpoint enqueued a background job
      # rather than doing the work inline, so the truthful status is 202.
      def render_queued(**extra)
        render json: { status: "queued" }.merge(extra), status: :accepted
      end

      def render_not_found(exception = nil)
        message = exception&.message || "Not found"
        render json: { error: message }, status: :not_found
      end

      def render_bad_request(exception = nil)
        render json: { error: exception&.message || "Bad request" }, status: :bad_request
      end

      # The raw RecordNotUnique message is PG constraint noise — return a
      # stable, human-readable envelope instead.
      def render_conflict(_exception = nil)
        render json: { error: "A record with these attributes already exists" }, status: :conflict
      end

      def render_unprocessable(exception = nil)
        errors = exception&.record&.errors&.full_messages || [ exception&.message ]
        # `error` matches every other handler's envelope; `errors` keeps the
        # full validation list for clients that render per-field messages.
        render json: { error: errors.first, errors: errors }, status: :unprocessable_content
      end

      def render_internal_error(exception = nil)
        Rails.logger.error(exception&.message)
        Rails.logger.error(exception&.backtrace&.first(5)&.join("\n"))
        if Current.household
          Activity.record(
            source:   "api",
            event:    "request.error",
            severity: Severity::Error,
            summary:  "#{request.method} #{request.path} raised #{exception&.class}: #{exception&.message}",
            payload:  { path: request.path, method: request.method }
          )
        end
        render json: { error: "Internal server error" }, status: :internal_server_error
      end
    end
  end
end
