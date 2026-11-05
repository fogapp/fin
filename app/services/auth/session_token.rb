# typed: strict

module Auth
  # The single place session tokens are minted. Session tokens are hidden
  # from the Personal Access Tokens list (which filters on session: false),
  # so every login/switch/replacement flow must set session: true — one of
  # five hand-rolled copies of this block forgot it, which is why this
  # service exists.
  class SessionToken
    extend T::Sig

    TTL = T.let(30.days, ActiveSupport::Duration)

    # oidc_sid is the provider's session behind a fog sign-in: a
    # back-channel logout naming it ends this token (SigninAdapter).
    sig do
      params(user: User, household: Household, label: String, oidc_sid: T.nilable(String),
        expires_at: T.nilable(ActiveSupport::TimeWithZone)).returns(ApiToken)
    end
    def self.mint!(user:, household:, label: "Passkey session", oidc_sid: nil, expires_at: nil)
      ApiToken.create!(
        name:       label,
        session:    true,
        user:       user,
        household:  household,
        expires_at: expires_at || TTL.from_now,
        oidc_sid:   oidc_sid,
      )
    end

    # A session that replaces the caller's own (household switch, household
    # delete). One from fog sign-in passes on what bounds it — the provider's
    # sid, so back-channel logout still finds it, and an expiry no later than
    # the one it replaces; any other is minted as before.
    sig { params(from: T.nilable(ApiToken), user: User, household: Household).returns(ApiToken) }
    def self.successor!(from:, user:, household:)
      sid = from&.session? ? from.oidc_sid : nil
      return mint!(user: user, household: household) if from.nil? || sid.nil?

      expires_at = TTL.from_now
      bound = from.expires_at
      expires_at = bound if bound && bound < expires_at
      mint!(user: user, household: household, label: from.name.presence || "Passkey session",
        oidc_sid: sid, expires_at: expires_at)
    end
  end
end
