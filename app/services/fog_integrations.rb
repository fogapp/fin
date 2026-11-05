# typed: strict
# frozen_string_literal: true

# The provider half of fog-integration/1 (fog:docs/integrations-contract.md),
# with consent: fog asks Fin for what another app on the box needs, a
# household admin approves it in Fin, and fog puts the credential in the
# app's environment.
#
# Fin's tokens are a person's: one acts as its owner in their household,
# on their money. So the operator's click in fog is not enough. The mint
# call answers a page on Fin's own console, /connect/<ticket>, and the
# request waits there, pending, until an admin of the household approves or
# declines it; approval mints a read-only API token in their name, named for
# the app ("fog: newtab"), and holds its plaintext encrypted until fog
# claims it, once. Nobody answers within TTL and it has expired.
#
# One offer, `finance`: the app reads what Fin holds — accounts,
# transactions, budget, cashflow, net worth — and changes nothing, since
# the token's scope is read (ApiTokenAuthentication). Fog authenticates
# with FOG_API_TOKEN (FogContractAuth); the integration's id is the row's,
# which fog keeps opaque and names again to claim, report on, or revoke.
module FogIntegrations
  extend T::Sig

  # Refused: fog shows the message to the operator, so each is a sentence.
  class Error < StandardError; end
  # No such integration or ticket.
  class NotFound < Error; end
  # Claimed before anyone approved it.
  class Waiting < Error; end
  # Declined, or answered already.
  class Answered < Error; end
  # Expired, or already claimed: nothing is left to have.
  class Gone < Error; end

  class Offer < T::Struct
    const :id, String
    const :title, String
    const :blurb, String
    # The secret the claim answers, as the offer in fog.yaml names it.
    const :secret, String
  end

  FINANCE = T.let(
    Offer.new(
      id: "finance", title: "Finances",
      blurb: "This app can read the household's accounts, transactions, budget, cashflow and net worth " \
             "in Fin, as the person who approves it, and change nothing.",
      secret: "FIN_API_TOKEN"
    ).freeze, Offer
  )
  OFFERS = T.let({ FINANCE.id => FINANCE }.freeze, T::Hash[String, Offer])

  # A fog app name (fog's apps.nameRe).
  CONSUMER_FORMAT = /\A[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?\z/
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  CONSENT_PATH = "/connect"

  class Asked < T::Struct
    const :id, String
    const :consent, String
  end

  class Status < T::Struct
    const :id, String
    const :active, T::Boolean
    const :created_at, ActiveSupport::TimeWithZone
    const :last_activity_at, T.nilable(ActiveSupport::TimeWithZone)
  end

  # POST /fog/integrations: record the request and answer the page a person
  # approves it on. return_to is where fog takes them back afterwards.
  sig { params(consumer: String, offer: String, return_to: T.nilable(String)).returns(Asked) }
  def self.ask(consumer:, offer:, return_to:)
    found = OFFERS[offer]
    raise Error, "Fin offers no #{offer.inspect} — it offers #{OFFERS.keys.join(", ")}" if found.nil?
    raise Error, "#{consumer.inspect} is not an app name" unless CONSUMER_FORMAT.match?(consumer)
    if return_to.blank?
      raise Error, "#{found.title} needs a person's approval in Fin — ask with a return_to to send them back to"
    end
    raise Error, "return_to must be an http(s) address" unless http_url?(return_to)

    household = Household.order(:created_at).first
    raise Error, "Fin has no household yet — open it and finish setup first" if household.nil?

    ticket = SecureRandom.urlsafe_base64(32)
    integration = FogIntegration.create!(
      household: household, consumer: consumer, offer: found.id,
      ticket_digest: digest(ticket), return_to: return_to, expires_at: FogIntegration::TTL.from_now
    )
    Asked.new(id: integration.id, consent: "#{CONSENT_PATH}/#{ticket}")
  end

  # The request a ticket names, within the current household (the console
  # API runs under the admin's household scope).
  sig { params(ticket: String).returns(FogIntegration) }
  def self.by_ticket(ticket)
    raise NotFound, "No such request — it may be for another household, or fog may have replaced it." if ticket.blank?

    integration = FogIntegration.find_by(ticket_digest: digest(ticket))
    raise NotFound, "No such request — it may be for another household, or fog may have replaced it." if integration.nil?

    integration
  end

  # The offer a request names; every stored offer is one Fin makes.
  sig { params(integration: FogIntegration).returns(Offer) }
  def self.offer_of(integration)
    T.must(OFFERS[integration.offer])
  end

  # A household admin says yes: the token is theirs, read-only, named for
  # the app; its plaintext waits, encrypted, for fog's claim.
  sig { params(ticket: String, by: User).returns(FogIntegration) }
  def self.approve!(ticket, by:)
    integration = by_ticket(ticket)
    integration.with_lock do
      refuse_unless_open!(integration)
      token = ApiToken.create!(user: by, household: integration.household, name: "fog: #{integration.consumer}",
        scope: ApiToken::Scope::Read)
      integration.update!(state: FogIntegration::State::Approved, api_token: token, approved_by: by,
        secret: token.raw_token)
    end
    Activity.record(source: "fog", event: "integration.approved", household_id: integration.household_id,
      summary: "#{by.name.presence || by.email} let #{integration.consumer} read Fin: a read-only API token in their name")
    integration
  end

  sig { params(ticket: String).returns(FogIntegration) }
  def self.decline!(ticket)
    integration = by_ticket(ticket)
    integration.with_lock do
      refuse_unless_open!(integration)
      integration.update!(state: FogIntegration::State::Declined)
    end
    integration
  end

  # Where the person goes after answering: fog's return_to, with the answer
  # beside the state fog put there.
  sig { params(integration: FogIntegration, result: String).returns(String) }
  def self.return_url(integration, result)
    uri = URI.parse(integration.return_to)
    query = URI.decode_www_form(uri.query.to_s)
    query << [ "result", result ]
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  # POST /fog/integrations/:id/claim: the secrets, once. The row lock makes
  # two racing claims one; the plaintext is wiped in the same transaction.
  sig { params(id: String).returns(T::Hash[String, String]) }
  def self.claim(id)
    integration = find(id)
    secret = T.let(nil, T.nilable(String))
    integration.with_lock do
      case integration.state
      when FogIntegration::State::Pending
        raise Gone, "This request expired before anyone approved it in Fin." if integration.expired?

        raise Waiting, "Nobody has approved this in Fin yet."
      when FogIntegration::State::Declined
        raise Answered, "Someone declined this in Fin."
      when FogIntegration::State::Claimed
        raise Gone, "This credential was already claimed; connect again for a new one."
      end
      secret = integration.secret
      raise Gone, "This credential is no longer held; connect again for a new one." if secret.blank?

      integration.update!(state: FogIntegration::State::Claimed, secret: nil, claimed_at: Time.current)
    end
    { offer_of(integration).secret => T.must(secret) }
  end

  # Active once claimed and while the token still works. A token revoked
  # from the token list leaves the row, which then reads as inactive.
  sig { params(id: String).returns(Status) }
  def self.status(id)
    integration = find(id)
    token = integration.api_token
    active = integration.claimed? && !token.nil? && !token.expired?
    Status.new(id: id, active: active, created_at: integration.created_at, last_activity_at: token&.last_used_at)
  end

  # Revoke the token, if any, and forget the request.
  sig { params(id: String).void }
  def self.disconnect(id)
    integration = find(id)
    token = integration.api_token
    ActiveRecord::Base.transaction do
      token&.destroy!
      integration.destroy!
    end
    return if token.nil?

    Activity.record(source: "fog", event: "integration.revoked", household_id: integration.household_id,
      summary: "fog disconnected #{integration.consumer} from Fin: its read-only API token is revoked")
  end

  sig { params(integration: FogIntegration).void }
  def self.refuse_unless_open!(integration)
    raise Gone, "This request has expired. Connect the app in fog again to get a new one." if integration.expired?
    raise Answered, "This request was already answered." unless integration.pending?
  end
  private_class_method :refuse_unless_open!

  sig { params(id: String).returns(FogIntegration) }
  def self.find(id)
    raise NotFound, "no such integration" unless id.match?(UUID)

    integration = FogIntegration.unscoped.includes(:api_token).find_by(id: id)
    raise NotFound, "no such integration" if integration.nil?

    integration
  end
  private_class_method :find

  sig { params(value: String).returns(String) }
  def self.digest(value)
    Digest::SHA256.hexdigest(value)
  end
  private_class_method :digest

  sig { params(value: String).returns(T::Boolean) }
  def self.http_url?(value)
    uri = URI.parse(value)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
  private_class_method :http_url?
end
