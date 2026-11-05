# typed: true

# Month/year query-param parsing shared by the reporting-style endpoints.
# Included in Api::V1::BaseController.
module PeriodParams
  extend ActiveSupport::Concern
  extend T::Sig

  # Module function so non-controller renderers (Api::Render::Review) can
  # share the exact same parsing without being controllers.
  sig { params(raw: T.untyped, default: Date).returns(Date) }
  def self.parse_month(raw, default:)
    return default.beginning_of_month if raw.blank?

    Date.strptime(raw.to_s, "%Y-%m").beginning_of_month
  rescue ArgumentError
    # Date::Error renders as a 400 via BaseController's rescue_from; the
    # rewrap gives the client the expected format instead of strptime noise.
    raise Date::Error, "month must be YYYY-MM"
  end

  private

  # Callers keep their own default period: budget and the subscriptions
  # calendar default to the current month, the monthly review to the
  # just-closed one.
  sig { params(default: Date).returns(Date) }
  def month_param(default: Date.current)
    PeriodParams.parse_month(params[:month].presence, default: default)
  end

  sig { returns(Integer) }
  def year_param
    (params[:year].presence || Date.current.year).to_i
  end
end
