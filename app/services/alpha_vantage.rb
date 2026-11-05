# typed: strict

# Namespace for the Alpha Vantage integration. Key resolution lives here
# because callers split into two shapes:
#
#   - household contexts (requests, per-household jobs): that household's
#     AlphaVantageConfiguration is authoritative.
#   - global contexts (MarketData::Scheduler, watched-by-anyone news sync):
#     candles/overviews/news are shared market data, so any household's
#     configured key serves the sync — resolved deterministically (oldest
#     configuration first).
#
# ENV["ALPHA_VANTAGE_API_KEY"] remains the last-resort fallback so existing
# deploys keep working until the key is entered in Settings → Integrations.
module AlphaVantage
  extend T::Sig

  sig { returns(T.nilable(String)) }
  def self.api_key
    if Current.household
      key = AlphaVantageConfiguration.current.api_key
      return key if key.present?
    end

    any_configured_key.presence || ENV["ALPHA_VANTAGE_API_KEY"].presence
  end

  sig { returns(T::Boolean) }
  def self.configured?
    api_key.present?
  end

  # Without Current.household, HouseholdScoped's default_scope is a no-op,
  # so this sees every household's row in both context shapes.
  sig { returns(T.nilable(String)) }
  def self.any_configured_key
    AlphaVantageConfiguration.unscoped.where.not(api_key: nil).order(:created_at).first&.api_key
  end
  private_class_method :any_configured_key
end
