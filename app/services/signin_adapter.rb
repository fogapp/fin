# typed: strict
# frozen_string_literal: true

# What fog sign-in means for Fin's own accounts (fog:docs/signin-proposal.md
# §15): FogClient::Signin::Rails asks, this answers in Fin's models. Fin
# keeps its users, its households and its session tokens; fog proves who
# someone is.
#
# Two things are Fin's own:
#
#   - Accounts have no passwords. An existing account is connected to a fog
#     identity only by its owner signing in to it with their Fin passkey
#     on the link page (account_from_request), never by email.
#   - A user may belong to several households, but a fog household is one
#     family. Fog's role is the person's role in the household fog stands
#     for — the oldest, the one the first sign-in creates — and new people
#     from fog join it. Their other memberships are Fin's business.
class SigninAdapter
  extend T::Sig

  ADMIN_ROLE = T.let(Role::Admin.serialize, String)
  # What a fog session is called in the token list, and the label the link
  # page's passkey proof carries.
  SESSION_LABEL = "fog session"
  # The link page's passkey proof (PasskeysController#link_finish): good for
  # five minutes, for one pending fog sign-in, and for nothing else.
  LINK_PROOF_PURPOSE = :fog_signin_link
  LINK_PROOF_TTL = T.let(5.minutes, ActiveSupport::Duration)

  sig { returns(String) }
  def admin_role = ADMIN_ROLE

  sig { params(issuer: String, subject: String).returns(T.nilable(User)) }
  def find_by_identity(issuer, subject)
    Identity.find_by(issuer: issuer, subject: subject)&.user
  end

  # SCIM-provisioned accounts carry the subject before anyone signs in
  # (signin-proposal §12); until Fin takes SCIM there are none.
  sig { params(subject: String).returns(T.nilable(User)) }
  def find_by_external_id(subject) = nil

  sig { returns(Integer) }
  def account_count = User.count

  # The first sign-in on a fresh Fin is its registration: a household with
  # the default workflows, and this person its admin — what /register does.
  sig { params(identity: FogClient::Signin::Identity).returns(User) }
  def bootstrap!(identity)
    ActiveRecord::Base.transaction do
      user = create_user(identity)
      found_household(user)
      user
    end
  end

  # A new account from fog joins the family's household with the role fog
  # gave them. On a Fin with no household yet the first person founds it
  # and administers it, as with registration.
  sig { params(identity: FogClient::Signin::Identity).returns(User) }
  def provision!(identity)
    ActiveRecord::Base.transaction do
      user = create_user(identity)
      household = fog_household
      if household
        HouseholdMembership.create!(user: user, household: household, role: role_for(identity))
      else
        found_household(user)
      end
      user
    end
  end

  sig { params(user: User, identity: FogClient::Signin::Identity).void }
  def link!(user, identity)
    Identity.create!(user: user, issuer: identity.issuer, subject: identity.subject)
    Activity.record(source: "signin", event: "signin.linked", subject: user,
      household_id: user.household_memberships.order(:created_at).pick(:household_id),
      summary: "#{user.email} now signs in with #{identity.handle.presence || 'a provider'} at #{identity.issuer}")
  end

  # Fin has no passwords: the link page proves an account with a passkey
  # instead (account_from_request).
  sig { params(login: String, password: String).returns(T.nilable(User)) }
  def authenticate_local(login, password) = nil

  # The link page's proof: the person signed in to their Fin account with
  # its passkey moments ago, for this pending fog sign-in, and sends the
  # proof that minted as a bearer token. The proof names the pending sign-in
  # it was made for, so it cannot connect any other. An account already
  # connected to someone at this provider is not offered again: one person
  # per account, so a passkey left on a shared device cannot hand someone
  # else's fog sign-in the account.
  sig { params(request: ActionDispatch::Request).returns(T.nilable(User)) }
  def account_from_request(request)
    header = request.headers["Authorization"].to_s
    return nil unless header.start_with?("Bearer ")

    proof = self.class.link_proof_verifier.verified(header.delete_prefix("Bearer "), purpose: LINK_PROOF_PURPOSE)
    return nil unless proof.is_a?(Hash)

    pending = request.params["pending"].to_s
    return nil unless ActiveSupport::SecurityUtils.secure_compare(proof["pending"].to_s, self.class.pending_digest(pending))

    user = User.find_by(id: proof["user_id"])
    issuer = FogClient::Signin.config&.issuer
    return nil if user.nil? || issuer.nil? || user.identities.exists?(issuer: issuer)

    user
  end

  # fog decided the role, for the household fog stands for; Fin refuses a
  # role it does not know, and never demotes that household's last admin.
  sig { params(user: User, role: String).void }
  def apply_role!(user, role)
    new_role = Role.try_deserialize(role)
    household = fog_household
    return if new_role.nil? || household.nil?

    membership = user.household_memberships.find_by(household_id: household.id)
    return if membership.nil? || membership.role == new_role

    if membership.admin? && household.household_memberships.where(role: Role::Admin).where.not(id: membership.id).none?
      Rails.logger.warn("fog sign-in: kept #{user.id} the admin of #{household.id}; it has no other")
      return
    end

    membership.update!(role: new_role)
  end

  # A session in the household the person joined first, as a passkey
  # sign-in lands. Its bearer token is only issued when the console redeems
  # the handoff code (ApiToken.redeem_handoff).
  sig { params(user: User, identity: FogClient::Signin::Identity).returns(String) }
  def start_session!(user, identity)
    household = user.household_memberships.order(:created_at).first&.household
    raise FogClient::Signin::Denied, "no_household" if household.nil?

    session = Auth::SessionToken.mint!(user: user, household: household, label: SESSION_LABEL, oidc_sid: identity.sid)
    session.issue_handoff!
  end

  # Ends session tokens only; personal API tokens are the person's own
  # credentials for scripts and are revoked in Settings.
  sig { params(sid: T.nilable(String), subject: T.nilable(String)).returns(Integer) }
  def end_sessions!(sid:, subject:)
    sessions = ApiToken.unscoped.where(session: true)
    if sid.present?
      sessions.where(oidc_sid: sid).destroy_all.size
    elsif subject.present?
      issuer = FogClient::Signin.config&.issuer
      return 0 if issuer.nil?

      sessions.where(user_id: Identity.where(issuer: issuer, subject: subject).select(:user_id)).destroy_all.size
    else
      0
    end
  end

  sig { params(pending: String).returns(String) }
  def self.pending_digest(pending) = Digest::SHA256.hexdigest("fog-signin pending:#{pending}")

  sig { returns(ActiveSupport::MessageVerifier) }
  def self.link_proof_verifier = Rails.application.message_verifier(LINK_PROOF_PURPOSE)

  # The proof PasskeysController#link_finish hands the link page.
  sig { params(user: User, pending: String).returns(String) }
  def self.issue_link_proof(user, pending)
    link_proof_verifier.generate({ "user_id" => user.id, "pending" => pending_digest(pending) },
      purpose: LINK_PROOF_PURPOSE, expires_in: LINK_PROOF_TTL)
  end

  # Whether a sealed pending sign-in is one this Fin issued and still
  # live — the passkey link ceremony is offered for nothing else.
  sig { params(pending: String).returns(T::Boolean) }
  def self.pending_valid?(pending)
    config = FogClient::Signin.config
    return false if config.nil? || pending.blank?

    FogClient::Signin::State.open(config, pending, purpose: "pending")["e"].to_i >= Time.now.to_i
  rescue FogClient::Signin::Error
    false
  end

  private

  # The household fog stands for: the oldest — the one the first sign-in
  # (or the first registration) founded.
  sig { returns(T.nilable(Household)) }
  def fog_household = Household.order(:created_at).first

  sig { params(user: User).returns(Household) }
  def found_household(user)
    household = Household.create!(name: "#{user.name.presence || user.email}'s Household")
    Households::SeedDefaultWorkflows.call(household)
    HouseholdMembership.create!(user: user, household: household, role: Role::Admin)
    household
  end

  sig { params(identity: FogClient::Signin::Identity).returns(String) }
  def role_for(identity)
    Role.try_deserialize(identity.role.to_s)&.serialize || Role::Member.serialize
  end

  # A fog person may have no email (Fin does not ask fog for one); Fin's
  # accounts need one. The stand-in is under .invalid (RFC 2606), so it can
  # never deliver or collide with a real address, and it is never used to
  # find anyone. An address the provider does send is kept only if no
  # account has it — it identifies nobody here.
  sig { params(identity: FogClient::Signin::Identity).returns(User) }
  def create_user(identity)
    email = identity.email.presence
    email = nil if email && User.exists?(email: email)
    local = identity.subject.split("/").last.to_s.downcase.gsub(/[^a-z0-9._-]/, "-")
    handle = identity.handle.to_s.downcase.gsub(/[^a-z0-9._-]/, "-").presence || "person"
    User.create!(
      email: email || "#{handle}.#{local}@fog.invalid",
      name: identity.name.presence || identity.handle.presence || "Someone",
    )
  end
end
