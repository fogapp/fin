# typed: strict

# Namespace for the CoinMarketCap integration. Key resolution lives here so
# every "is CoinMarketCap usable?" check agrees with what the client will
# actually authenticate with:
#
#   - household contexts (requests, per-household jobs): that household's
#     CoinMarketCapConfiguration, falling back to ENV.
#   - global contexts (MarketData::Router): any household's configured key,
#     or ENV.
#
# ENV["COINMARKETCAP_API_KEY"] remains the last-resort fallback for deploys
# that predate the Settings → Integrations entry.
module CoinMarketCap
  extend T::Sig

  # Defined here (not in client.rb) so referencing CoinMarketCap::RateLimitError
  # — e.g. from a job's rescue — never depends on Client having been
  # autoloaded first.
  class Error < StandardError; end
  class RateLimitError < Error; end
  class MissingKeyError < Error; end

  sig { returns(T.nilable(String)) }
  def self.api_key
    household_key = CoinMarketCapConfiguration.current.api_key.presence if Current.household
    household_key || ENV["COINMARKETCAP_API_KEY"].presence
  end

  sig { returns(T::Boolean) }
  def self.configured?
    api_key.present?
  end

  # Whether any household (or ENV) can authenticate — for global contexts.
  # Without Current.household, HouseholdScoped's default_scope is a no-op.
  sig { returns(T::Boolean) }
  def self.any_configured?
    ENV["COINMARKETCAP_API_KEY"].present? ||
      CoinMarketCapConfiguration.unscoped.where.not(api_key: nil).exists?
  end
end
