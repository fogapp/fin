# typed: true

class WorkflowRun < ApplicationRecord
  extend T::Sig

  include HouseholdScoped

  # Run lifecycle states. Pending/running/waiting are the live states a
  # stranded or resumed executor may pick back up; the rest are terminal.
  class Status < T::Enum
    include ApplicationEnum

    enums do
      Pending = new("pending")
      Running = new("running")
      Waiting = new("waiting")
      Completed = new("completed")
      Failed = new("failed")
      Cancelled = new("cancelled")
    end
  end

  UNFINISHED_STATUSES = T.let(
    [ Status::Pending, Status::Running, Status::Waiting ].freeze,
    T::Array[Status]
  )

  typed_enum :status, Status

  belongs_to :workflow
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :triggered_by_run, class_name: "WorkflowRun", optional: true
  has_many :run_steps, -> { order(:created_at) },
           class_name: "WorkflowRunStep", dependent: :destroy

  validates :event_type, presence: true

  before_create { T.bind(self, WorkflowRun); self.trace_id ||= Current.trace_id }

  scope :recent, -> { order(created_at: :desc) }

  # Workflow ids of every run in the triggered_by ancestry — used to stop
  # run chains from looping and to cap chain depth.
  sig { returns(T::Array[String]) }
  def ancestor_workflow_ids
    ids     = []
    visited = Set.new
    node    = T.let(triggered_by_run, T.nilable(WorkflowRun))

    while node
      break if visited.include?(node.id)

      visited << node.id
      ids << node.workflow_id
      node = node.triggered_by_run
    end

    ids
  end

  sig { returns(Integer) }
  def chain_depth
    ancestor_workflow_ids.size
  end
end
