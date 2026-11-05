# typed: strict

module Auth
  # Signed links whose bearer may enroll a passkey for an existing user —
  # the one way into an account other than a passkey it already has.
  #
  # Two shapes share the token:
  #
  #   - a device invite: fifteen minutes, for adding a second device at this
  #     address (Settings → Devices).
  #   - a sign-in link for another address: a week, for moving the instance.
  #     Passkeys are bound to the address they were registered on, so after
  #     a restore elsewhere nobody can sign in; a link issued here, before
  #     the move, verifies there because the restored instance carries the
  #     same SECRET_KEY_BASE (the backup preflight insists on it).
  #
  # The long-lived shape is narrowed to make up for its lifetime: it names
  # the one host it may be redeemed on, and it dies with its first use.
  # There is no row to mark used — the token has to work on an instance
  # restored from a backup taken before it was issued — so "used" is read
  # from the account instead: any passkey newer than the link supersedes it.
  module DeviceInvite
    extend T::Sig

    INTENT = T.let("device_invite", String)
    TTL = T.let(15.minutes, ActiveSupport::Duration)
    MOVE_TTL = T.let(7.days, ActiveSupport::Duration)

    class Rejected < StandardError; end

    # Where a moved instance will live, as typed by a person: a bare host,
    # host:port, or a full URL. https unless they said otherwise.
    class Address < T::Struct
      extend T::Sig

      const :host, String
      const :origin, String

      sig { params(token: String).returns(String) }
      def join_url(token) = "#{origin}/join-device?token=#{CGI.escape(token)}"
    end

    class Issued < T::Struct
      const :token, String
      const :expires_at, ActiveSupport::TimeWithZone
    end

    sig { params(input: String).returns(T.nilable(Address)) }
    def self.parse_address(input)
      text = input.strip
      text = "https://#{text}" unless text.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
      uri = URI.parse(text)
      host = uri.host&.downcase
      return nil unless uri.is_a?(URI::HTTP) && host.present? && uri.userinfo.nil?

      default_port = uri.scheme == "https" ? 443 : 80
      port = uri.port == default_port ? "" : ":#{uri.port}"
      Address.new(host: host, origin: "#{uri.scheme}://#{host}#{port}")
    rescue URI::Error
      nil
    end

    sig { params(user: User, host: T.nilable(String)).returns(Issued) }
    def self.issue(user:, host: nil)
      ttl = host ? MOVE_TTL : TTL
      payload = { intent: INTENT, user_id: user.id, email: user.email, name: user.name }
      payload = payload.merge(host: host, issued_at: Time.current.to_f) if host

      Issued.new(token: verifier.generate(payload, expires_in: ttl), expires_at: ttl.from_now)
    end

    # The verified payload. An expired or tampered token raises
    # MessageVerifier::InvalidSignature (PasskeysController renders it as a
    # 401); a genuine token that may not be used here raises Rejected.
    sig { params(token: String, request_host: String).returns(T::Hash[String, T.untyped]) }
    def self.verify!(token, request_host:)
      payload = verifier.verify(token)
      raise Rejected, "This link is not a device invite." unless payload["intent"] == INTENT

      bound = payload["host"].presence
      if bound && !bound.casecmp?(request_host)
        raise Rejected, "This link was issued for #{bound} — open it there."
      end
      if bound && superseded?(payload)
        raise Rejected, "This link has already been used. Ask for a new one."
      end

      payload
    end

    sig { params(payload: T::Hash[String, T.untyped]).returns(T::Boolean) }
    def self.superseded?(payload)
      issued_at = Time.zone.at(payload["issued_at"].to_f)
      WebauthnCredential.where(user_id: payload["user_id"]).where("created_at > ?", issued_at).exists?
    end
    private_class_method :superseded?

    sig { returns(ActiveSupport::MessageVerifier) }
    def self.verifier = Rails.application.message_verifier(:device_invite)
    private_class_method :verifier
  end
end
