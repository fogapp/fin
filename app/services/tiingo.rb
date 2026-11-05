# typed: strict

# Namespace for the Tiingo integration. Key resolution mirrors AlphaVantage:
#
#   - household contexts (requests, per-household jobs): that household's
#     TiingoConfiguration is authoritative.
#   - global contexts (MarketData::Scheduler, cross-checks): candles are
#     shared market data, so any household's configured key serves the sync —
#     resolved deterministically (oldest configuration first).
#
# ENV["TIINGO_API_KEY"] remains the last-resort fallback for deploys that
# predate the Settings → Integrations entry.
module Tiingo
  extend T::Sig

  # Defined here (not in client.rb) so referencing Tiingo::RateLimitError —
  # e.g. from the scheduler or specs — never depends on Client having been
  # autoloaded first.
  class Error < StandardError; end
  class RateLimitError < Error; end
  class MissingKeyError < Error; end

  sig { returns(T.nilable(String)) }
  def self.api_key
    if Current.household
      key = TiingoConfiguration.current.api_key
      return key if key.present?
    end

    any_configured_key.presence || ENV["TIINGO_API_KEY"].presence
  end

  sig { returns(T::Boolean) }
  def self.configured?
    api_key.present?
  end

  # Without Current.household, HouseholdScoped's default_scope is a no-op,
  # so this sees every household's row in both context shapes.
  sig { returns(T.nilable(String)) }
  def self.any_configured_key
    TiingoConfiguration.unscoped.where.not(api_key: nil).order(:created_at).first&.api_key
  end
  private_class_method :any_configured_key
end
