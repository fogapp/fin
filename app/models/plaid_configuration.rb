# typed: true

class PlaidConfiguration < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  include HouseholdConfiguration

  encrypts :client_id, :secret
  configured_when :client_id, :secret

  # Which Plaid stack the stored credentials belong to.
  class Environment < T::Enum
    extend T::Sig

    include ApplicationEnum

    enums do
      Sandbox = new("sandbox")
      Production = new("production")
    end
  end

  typed_enum :environment, Environment

  # The Plaid stack used when nothing names one: PLAID_ENV if set, otherwise
  # production for a production deployment and sandbox everywhere else.
  # (Plaid retired its "development" stack; production now serves it.)
  sig { returns(String) }
  def self.default_environment
    env = ENV["PLAID_ENV"].presence
    return "production" if env == "development"

    env || (Rails.env.production? ? "production" : "sandbox")
  end

  # A household's first row targets the deployment's Plaid stack.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def self.configuration_defaults
    { environment: default_environment }
  end
end
