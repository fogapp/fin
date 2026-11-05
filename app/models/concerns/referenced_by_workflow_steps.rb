# typed: false

# Workflow action steps store the ids they act on inside their JSON config
# (e.g. assign_category → params.category_id). Deleting the referenced
# record leaves those steps pointing at nothing, and the next run fails
# quietly. Models a step can reference declare it, and destroying one raises
# an Issue per orphaned step so the user knows to fix the workflow:
#
#   flags_orphaned_workflow_steps "assign_category", param: "category_id",
#                                 action_label: "assign category"
#
# The params value may be a single id or an array of ids (add_tag); jsonb
# containment (`@>`) matches both.
module ReferencedByWorkflowSteps
  extend ActiveSupport::Concern

  included do
    class_attribute :workflow_step_references, instance_accessor: false, default: []
    after_destroy :flag_orphaned_workflow_steps
  end

  class_methods do
    def flags_orphaned_workflow_steps(action_type, param:, action_label:)
      self.workflow_step_references = workflow_step_references + [
        { action_type: action_type, param: param, action_label: action_label }
      ]
    end
  end

  private

  def flag_orphaned_workflow_steps
    noun = self.class.model_name.human.downcase
    self.class.workflow_step_references.each do |ref|
      orphaned_workflow_steps(ref).each do |step|
        Issue.raise_once!(
          key:      "orphaned_workflow_step:#{step.id}",
          title:    "Workflow step references deleted #{noun}",
          body:     "The workflow \"#{step.workflow.name}\" has a \"#{ref[:action_label]}\" action that pointed to \"#{orphan_display_name}\", which has been deleted. Edit or remove that step.",
          severity: Severity::Warning,
          source:   "workflow:#{step.workflow_id}"
        )
      end
    end
  end

  def orphaned_workflow_steps(ref)
    WorkflowStep
      .joins(:workflow)
      .includes(:workflow)
      .where(kind: WorkflowStep::Kind::Action)
      .where("workflow_steps.config->>'action_type' = ?", ref[:action_type])
      .where("workflow_steps.config->'params'->? @> to_jsonb(?::text)", ref[:param], id)
      .where(workflows: { household_id: household_id })
  end

  def orphan_display_name
    respond_to?(:name) ? name : id
  end
end
