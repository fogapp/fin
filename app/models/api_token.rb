# typed: true

class ApiToken < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  belongs_to :user

  # What a token may do. Full is the default and what every token has been:
  # whatever its user can do in the household. Read answers GET and HEAD and
  # the read-only MCP tools only (ApiTokenAuthentication enforces it), for a
  # credential that shows the household's money to another app without
  # being able to move it.
  class Scope < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Full = new("full")
      Read = new("read")
    end
  end

  typed_enum :scope, Scope

  before_validation :generate_token, on: :create

  validates :token_digest, presence: true, uniqueness: true

  # The callback hands the console a code, not the token: the code rides in
  # a URL fragment for one redirect and is good once, for a minute
  # (fog:docs/signin-proposal.md §15).
  HANDOFF_TTL = T.let(1.minute, ActiveSupport::Duration)

  # The plaintext token, available only in memory on the instance that
  # generated it — never persisted. Render it to the client once, at creation.
  sig { returns(T.nilable(String)) }
  attr_reader :raw_token

  sig { params(raw_token: String).returns(T.nilable(ApiToken)) }
  def self.authenticate(raw_token)
    digest = Digest::SHA256.hexdigest(raw_token)
    find_by(token_digest: digest)
  end

  sig { returns(T::Boolean) }
  def expired?
    ea = expires_at
    !!(ea.present? && ea < Time.current)
  end

  sig { returns(T::Boolean) }
  def read_only?
    scope == Scope::Read
  end

  # A one-time code the console exchanges for this session's token. The
  # plaintext token was never kept, so the exchange mints a fresh one for
  # this row (redeem_handoff); until then nobody holds a usable token.
  sig { params(ttl: ActiveSupport::Duration).returns(String) }
  def issue_handoff!(ttl: HANDOFF_TTL)
    code = SecureRandom.urlsafe_base64(32)
    update!(handoff_digest: Digest::SHA256.hexdigest(code), handoff_expires_at: ttl.from_now)
    code
  end

  # The session a handoff code names, carrying its new plaintext token in
  # raw_token — once: two racing redemptions cannot both win, because the
  # database spends the code in the same statement that rekeys the row.
  sig { params(code: String).returns(T.nilable(ApiToken)) }
  def self.redeem_handoff(code)
    return nil if code.blank?

    digest = Digest::SHA256.hexdigest(code)
    token = unscoped.find_by(handoff_digest: digest)
    return nil if token.nil?

    token.send(:rekey_for_handoff, digest) ? token : nil
  end

  # Called on every authenticated request; throttled so it's one UPDATE per
  # minute per token instead of one per request.
  sig { returns(T::Boolean) }
  def touch_last_used!
    last = last_used_at
    return true if last && last > 1.minute.ago

    update_column(:last_used_at, Time.current)
  end

  private

  sig { params(digest: String).returns(T::Boolean) }
  def rekey_for_handoff(digest)
    raw = SecureRandom.hex(32)
    spent = ApiToken.unscoped
      .where(id: id, handoff_digest: digest).where("handoff_expires_at > ?", Time.current)
      .update_all(token_digest: Digest::SHA256.hexdigest(raw), handoff_digest: nil, handoff_expires_at: nil) # rubocop:disable Rails/SkipsModelValidations
    return false unless spent == 1

    reload
    return false if expired?

    @raw_token = raw
    true
  end

  sig { void }
  def generate_token
    return if token_digest.present?
    @raw_token        = SecureRandom.hex(32)
    self.token_digest = Digest::SHA256.hexdigest(T.must(@raw_token))
  end
end
