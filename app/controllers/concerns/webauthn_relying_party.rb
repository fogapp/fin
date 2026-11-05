# typed: true

# Builds a per-request WebAuthn::RelyingParty derived from the request's host,
# so a deployment works on any domain with zero configuration. Env vars
# (FIN_WEBAUTHN_RP_ID / FIN_WEBAUTHN_ORIGINS / FIN_WEBAUTHN_RP_NAME)
# remain as overrides for setups where the API host isn't the page's domain.
#
# The RP ID is what binds a passkey to the site; changing it invalidates every
# previously-registered credential.
module WebauthnRelyingParty
  extend ActiveSupport::Concern
  extend T::Helpers

  # The includer (PasskeysController) descends from ActionController::API
  # directly — it runs unauthenticated; declaring it lets Sorbet resolve
  # `request` here instead of reporting it undefined on the module.
  requires_ancestor { ActionController::API }

  EXTRA_ALGORITHMS = %w[ES384 ES512 RS384 RS512 PS384 PS512].freeze

  included do
    T.bind(self, T.class_of(ActionController::API))

    # The gem is `require: false` in the Gemfile (see the note there), so it
    # has to be loaded before any WebAuthn:: constant is touched. A callback
    # rather than a call at the top of #webauthn_relying_party because the
    # controllers also reference WebAuthn::Credential and rescue
    # WebAuthn::Error directly, and a `rescue` clause resolves its constant at
    # raise time — a NameError there would mask the real ceremony failure.
    before_action :load_webauthn!
  end

  private

  # Idempotent and cheap after the first call ($LOADED_FEATURES lookup); the
  # ~12 MB is paid once, by whichever process first serves a passkey request.
  def load_webauthn!
    require "webauthn"
  end

  def webauthn_relying_party
    @webauthn_relying_party ||= begin
      rp_id = ENV["FIN_WEBAUTHN_RP_ID"].presence || request.host
      WebAuthn::RelyingParty.new(
        id:              rp_id,
        name:            ENV["FIN_WEBAUTHN_RP_NAME"].presence || "Fin",
        allowed_origins: webauthn_allowed_origins(rp_id),
        algorithms:      WebAuthn::RelyingParty::DEFAULT_ALGORITHMS + EXTRA_ALGORITHMS
      )
    end
  end

  # WebAuthn requires a stable, opaque user handle (not the email). We
  # derive it from the email so the same user gets the same handle on
  # the second enrollment device. URL-safe base64, 64 bytes max per spec.
  def webauthn_user_handle(email)
    Base64.urlsafe_encode64(
      OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "webauthn-uid:#{email}")
    )
  end

  def sign_challenge(payload)
    Rails.application.message_verifier(:webauthn).generate(
      payload.merge(issued_at: Time.current.to_i),
      expires_in: 5.minutes
    )
  end

  # An expired/tampered token raises MessageVerifier::InvalidSignature —
  # deliberately not rescued here: PasskeysController's class-level
  # rescue_from renders it as a clean 401.
  def read_challenge(intent:)
    token = params.require(:challenge_token)
    payload = Rails.application.message_verifier(:webauthn).verify(token)
    raise WebAuthn::Error, "intent mismatch" unless payload["intent"] == intent
    payload
  end

  # Creation-ceremony options shared by every enrollment path (register,
  # device invite): one place owns the authenticator
  # selection policy and the handle/display-name derivation. `user` may be
  # unpersisted (registration validates before saving), so the caller
  # supplies the email and the exclude list explicitly.
  def creation_options_for(user, email:, exclude:)
    WebAuthn::Credential.options_for_create(
      user: {
        id:           webauthn_user_handle(email),
        name:         email,
        display_name: user.name.presence || email
      },
      exclude: exclude,
      authenticator_selection: { user_verification: "preferred", resident_key: "preferred" },
      relying_party: webauthn_relying_party
    )
  end

  # The origins a ceremony will accept. Two independent sources, UNIONED
  # rather than one silently winning: the explicit env override and the
  # origins derived from the request itself. An override that expands to
  # something no browser can ever send (a deploy that templated an empty
  # hostname into "https://", say) then degrades to a no-op instead of
  # locking every passkey out of the instance.
  def webauthn_allowed_origins(rp_id)
    origins = (configured_webauthn_origins + request_webauthn_origins(rp_id)).uniq
    warn_unmatchable_webauthn_origins(origins, rp_id)
    origins
  end

  # Entries that aren't a bare http(s) origin are dropped with a warning:
  # a host with no scheme, a URL with a path, or the degenerate "https://"
  # can only ever fail the comparison, and failing loudly at the log beats
  # OriginVerificationError on every ceremony.
  def configured_webauthn_origins
    entries = ENV["FIN_WEBAUTHN_ORIGINS"].to_s.split(",").map(&:strip).reject(&:empty?)
    normalized = entries.index_with { |entry| normalize_webauthn_origin(entry) }
    junk = normalized.select { |_, origin| origin.nil? }.keys
    if junk.any?
      Rails.logger.warn(
        "[webauthn] ignoring unusable FIN_WEBAUTHN_ORIGINS entries #{junk.inspect} — " \
        "each must be a scheme + host, e.g. https://fin.example.com"
      )
    end
    normalized.values.compact.uniq
  end

  # The API's own origin covers the same-origin production setup. The Origin
  # header covers dev, where the Vite page (localhost:5173) calls the API on
  # another port, and any proxy chain that loses the forwarded scheme or port
  # — admitted only when the browser's own rp_id rule would have permitted
  # the ceremony, since that check is what anchors phishing protection.
  def request_webauthn_origins(rp_id)
    origins = [ normalize_webauthn_origin(request.base_url) ]
    header  = request.headers["Origin"].presence
    origins << normalize_webauthn_origin(header) if header && webauthn_origin_under_rp?(header, rp_id)
    origins.compact.uniq
  end

  # WebAuthn lets the RP ID be the origin's host or a registrable suffix of
  # it (an origin on app.example.com may claim rp_id example.com), so match
  # the same relation rather than equality alone.
  def webauthn_origin_under_rp?(origin, rp_id)
    host = begin
      URI.parse(origin).host&.downcase
    rescue URI::Error
      nil
    end
    return false if host.nil? || rp_id.blank?

    rp = rp_id.downcase
    host == rp || host.end_with?(".#{rp}")
  end

  # Canonical form for comparison against the browser's clientData origin:
  # scheme + host, plus the port only when it isn't the scheme's default
  # (a browser never sends ":443" on an https origin). Returns nil for
  # anything that isn't a usable origin, which is also the validity test.
  def normalize_webauthn_origin(value)
    uri = URI.parse(value.to_s.strip.sub(%r{/+\z}, ""))
    return nil unless uri.is_a?(URI::HTTP)

    scheme = uri.scheme&.downcase
    host   = uri.host&.downcase
    return nil if scheme.blank? || host.blank?
    return nil if uri.userinfo.present? || uri.query.present? || uri.fragment.present?
    return nil if uri.path.present?

    port = uri.port
    return "#{scheme}://#{host}" if port.nil? || port == (scheme == "https" ? 443 : 80)

    "#{scheme}://#{host}:#{port}"
  rescue URI::Error
    nil
  end

  # The single line that turns this class of misconfiguration from a silent
  # 422 into an obvious one: if the browser's own origin isn't in the list,
  # no ceremony from this page can ever verify.
  def warn_unmatchable_webauthn_origins(origins, rp_id)
    header = request.headers["Origin"].presence
    return if header.nil?

    normalized = normalize_webauthn_origin(header)
    return if normalized && origins.include?(normalized)

    Rails.logger.warn(
      "[webauthn] request Origin #{header.inspect} is not in allowed origins #{origins.inspect} " \
      "(rp_id #{rp_id.inspect}) — every ceremony from this page will fail OriginVerificationError. " \
      "Check FIN_WEBAUTHN_ORIGINS / FIN_WEBAUTHN_RP_ID, or unset both to derive them from the request."
    )
  end
end
