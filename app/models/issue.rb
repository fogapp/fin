# typed: true

class Issue < ApplicationRecord
  include HouseholdScoped

  validates :title, presence: true
  typed_enum :severity, Severity

  scope :active, -> { where(dismissed_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Idempotent create-or-update for audit checks. Reopens a previously dismissed
  # issue if the same condition fires again. Title/body/severity are always refreshed
  # so stale descriptions don't persist.
  def self.raise_once!(key:, title:, body: nil, severity: Severity::Warning, source: nil)
    refresh!(find_or_initialize_by(key: key), title:, body:, severity:, source:)
  end

  # raise_once! for an audit that raises one issue per row: one read for
  # every key instead of one per issue. Each hash takes raise_once!'s
  # keywords; an issue that is already open and unchanged writes nothing.
  def self.raise_each!(issues)
    existing = where(key: issues.pluck(:key)).index_by(&:key)
    issues.each do |attrs|
      issue = existing[attrs[:key]] || new(key: attrs[:key])
      refresh!(issue, **attrs.slice(:title, :body, :severity, :source))
    end
  end

  def self.refresh!(issue, title:, body: nil, severity: Severity::Warning, source: nil)
    issue.assign_attributes(
      title:        title,
      body:         body,
      severity:     severity,
      source:       source,
      dismissed_at: nil
    )
    issue.save!
    issue
  rescue ActiveRecord::RecordNotUnique
    # Race condition on parallel audit runs — safe to ignore
    nil
  end
  private_class_method :refresh!

  # Auto-dismiss an open issue by key when the underlying condition clears.
  def self.resolve!(key)
    active.where(key: key).update_all(dismissed_at: Time.current)
  end

  def dismiss!
    update!(dismissed_at: Time.current)
  end
end
