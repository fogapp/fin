# typed: true

class ActivityEntry < ApplicationRecord
  include HouseholdScoped

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :caused_by, polymorphic: true, optional: true

  validates :source, :event, :summary, :occurred_at, presence: true
  typed_enum :severity, Severity

  scope :recent,     -> { order(occurred_at: :desc, created_at: :desc) }
  scope :for_trace,  ->(trace_id) { where(trace_id: trace_id) }
  scope :errors,     -> { where(severity: Severity::Error) }
end
