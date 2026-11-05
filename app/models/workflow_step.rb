# typed: true

class WorkflowStep < ApplicationRecord
  extend T::Sig

  # Step node types: `branch` steps form if/elsif chains, `action` steps
  # execute a Workflows::ActionType, `wait` steps park the run.
  class Kind < T::Enum
    include ApplicationEnum

    enums do
      Branch = new("branch")
      Action = new("action")
      Wait = new("wait")
    end
  end

  typed_enum :kind, Kind

  belongs_to :workflow
  belongs_to :parent, class_name: "WorkflowStep", optional: true
  has_many :children, -> { order(:position) },
           class_name: "WorkflowStep", foreign_key: :parent_id,
           dependent: :destroy, inverse_of: :parent

  validate  :parent_belongs_to_same_workflow
  validate  :config_shape

  sig { returns(T::Boolean) }
  def branch? = kind == Kind::Branch

  # Branch config accessors
  sig { returns(T::Boolean) }
  def else_branch? = branch? && config["else"] == true

  sig { returns(T::Boolean) }
  def match_all? = config.fetch("match_all", true) != false

  sig { returns(T::Array[T.untyped]) }
  def conditions
    Array(config["conditions"]).map do |c|
      Condition.new(c["field"].to_s, c["operator"].to_s, c["value"].to_s)
    end
  end

  Condition = Struct.new(:field, :operator, :value)

  private

  def parent_belongs_to_same_workflow
    parent_step = parent
    return if parent_step.nil? || parent_step.workflow_id == workflow_id

    errors.add(:parent_id, "must belong to the same workflow")
  end

  def config_shape
    case kind
    when Kind::Action
      errors.add(:config, "action steps need an action_type") if config["action_type"].blank?
    when Kind::Wait
      unless config["duration_seconds"].to_i.positive?
        errors.add(:config, "wait steps need a positive duration_seconds")
      end
    when Kind::Branch
      if config["else"] != true && Array(config["conditions"]).empty?
        errors.add(:config, "branch steps need conditions (or else: true)")
      end
    end
  end
end
