# typed: true

class WorkflowMonitorState < ApplicationRecord
  belongs_to :workflow

  validates :subject_type, :subject_id, presence: true
end
