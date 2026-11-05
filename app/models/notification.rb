# typed: true

class Notification < ApplicationRecord
  include HouseholdScoped

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :workflow_run, optional: true

  validates :title, presence: true
  typed_enum :severity, Severity

  before_create { T.bind(self, Notification); self.trace_id ||= Current.trace_id }
  # On fog, every notification also goes to the household event stream for a
  # reader such as HUD; off fog there is nowhere to send it.
  after_create_commit { T.bind(self, Notification); PublishNotificationEventJob.perform_later(id) if FogEvents.available? }

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }
end
