# typed: true

# One instrument becoming another — an unsponsored ADR replaced by a
# sponsored one, a ticker/CUSIP change, a stock-for-stock merger — that the
# transaction ledger never records. Valuation treats a confirmed conversion
# as a same-day transfer: every account's from_security shares leave and
# ratio × those shares of to_security arrive on effective_date. Without it
# the custodian anchor carries the new instrument's unexplained shares back
# to the start of history while the old instrument is still counted.
#
# Detection proposes conversions as suggested; only confirmed ones affect
# valuation, and a dismissed one is never suggested again.
class SecurityConversion < ApplicationRecord
  extend T::Sig

  include HouseholdScoped
  # Confirming, dismissing or deleting one changes every valuation.
  include BumpsHouseholdDataVersion

  class Status < T::Enum
    include ApplicationEnum

    enums do
      Suggested = new("suggested")
      Confirmed = new("confirmed")
      Dismissed = new("dismissed")
    end
  end

  class Source < T::Enum
    include ApplicationEnum

    enums do
      Detected = new("detected")
      Manual = new("manual")
    end
  end

  typed_enum :status, Status
  typed_enum :source, Source

  belongs_to :from_security, class_name: "Security"
  belongs_to :to_security, class_name: "Security"

  validates :effective_date, presence: true
  validates :ratio, numericality: { greater_than: 0 }
  validate :distinct_securities

  scope :confirmed, -> { where(status: Status::Confirmed.serialize) }
  scope :suggested, -> { where(status: Status::Suggested.serialize) }

  ISSUE_KEY_PREFIX = "security_conversion:"

  after_destroy_commit :resolve_issue

  sig { returns(String) }
  def issue_key = "#{ISSUE_KEY_PREFIX}#{id}"

  sig { void }
  def confirm!
    update!(status: Status::Confirmed, confirmed_at: Time.current)
    Issue.resolve!(issue_key)
    refresh_portfolio_metric
  end

  sig { void }
  def dismiss!
    update!(status: Status::Dismissed, confirmed_at: nil)
    Issue.resolve!(issue_key)
  end

  # Suggested conversions wait on the user, so each gets its own issue.
  sig { void }
  def raise_issue!
    Issue.raise_once!(
      key:      issue_key,
      title:    "Possible conversion: #{label(from_security)} → #{label(to_security)}" \
                "#{account_name ? " in #{account_name}" : ''} (#{effective_date.strftime('%b %-d, %Y')})",
      body:     issue_body,
      severity: Severity::Warning,
      source:   "system_audit"
    )
  end

  # The stored portfolio_value history predates the conversion; recompute it
  # rather than wait for the nightly refresh, whose trailing window never
  # reaches back to most effective dates.
  sig { void }
  def refresh_portfolio_metric
    Metrics::BackfillJob.perform_later(household_id, "portfolio_value")
  end

  private

  sig { void }
  def distinct_securities
    errors.add(:to_security, "must differ from the security being converted") if from_security_id == to_security_id
  end

  sig { void }
  def resolve_issue
    Issue.resolve!(issue_key)
  end

  sig { returns(T.nilable(String)) }
  def account_name
    evidence.is_a?(Hash) ? evidence["account_name"].presence : nil
  end

  sig { params(security: T.nilable(Security)).returns(String) }
  def label(security)
    security&.ticker.presence || security&.name.to_s.truncate(40)
  end

  sig { returns(String) }
  def issue_body
    from = evidence["from"] || {}
    to   = evidence["to"] || {}
    parts = [
      "#{label(from_security)} stopped trading after #{from['last_close_date']} while the ledger still holds " \
      "#{from['ledger_quantity']} shares, and the custodian reports #{to['unexplained_quantity']} " \
      "#{label(to_security)} shares the ledger never saw.",
      "Suggested ratio: #{ratio.to_f.round(4)} #{label(to_security)} per #{label(from_security)} share " \
      "(current, split-adjusted units), effective #{effective_date.iso8601}."
    ]
    parts << "Value across the switch differs by #{evidence['value_gap_pct']}%." if evidence["value_gap_pct"]
    parts << "Confirm it so valuations treat the two as one holding changing instruments, or dismiss it."
    parts.join(" ")
  end
end
