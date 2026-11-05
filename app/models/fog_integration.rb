# typed: strict
# frozen_string_literal: true

# An app fog asked to connect to Fin (FogIntegrations). Pending until a
# household admin answers at /connect/<ticket>; approved, it holds the
# read-only API token minted for the app and its plaintext (encrypted) until
# fog claims it; claimed, it names the token fog reports on and revokes.
class FogIntegration < ApplicationRecord
  extend T::Sig

  include HouseholdScoped

  # How long fog waits for someone to answer (the contract's 30 minutes).
  TTL = T.let(30.minutes, ActiveSupport::Duration)

  class State < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Pending = new("pending")
      Approved = new("approved")
      Declined = new("declined")
      Claimed = new("claimed")
    end
  end

  typed_enum :state, State

  belongs_to :api_token, optional: true
  belongs_to :approved_by, class_name: "User", optional: true

  encrypts :secret

  validates :consumer, :offer, :ticket_digest, :return_to, :expires_at, presence: true

  sig { returns(T::Boolean) }
  def pending?
    state == State::Pending
  end

  sig { returns(T::Boolean) }
  def claimed?
    state == State::Claimed
  end

  # A request nobody answered in time. Only a pending one expires: an
  # answer, once given, stands.
  sig { returns(T::Boolean) }
  def expired?
    pending? && expires_at < Time.current
  end

  # The state as the consent page shows it: a pending request past its time
  # reads as expired.
  sig { returns(String) }
  def shown_state
    expired? ? "expired" : state.serialize
  end
end
