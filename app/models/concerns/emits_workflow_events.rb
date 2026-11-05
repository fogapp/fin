# typed: false

# Publishes lifecycle events (<key>.created / .updated / .deleted) into the
# workflow engine for models in Workflows::Catalog::RECORD_MODELS. The
# publish call is a near no-op unless the household has an active workflow
# listening for that event type.
module EmitsWorkflowEvents
  extend ActiveSupport::Concern

  # Attributes that never count as meaningful changes for `updated` events.
  IGNORED_CHANGE_KEYS = %w[updated_at created_at].freeze

  # Attributes included in the payload snapshot for `deleted` events (the
  # subject row is gone by the time the run executes).
  SNAPSHOT_KEYS = %w[id name description amount transaction_date trade_date status].freeze

  included do
    after_create_commit  :emit_workflow_created_event
    after_update_commit  :emit_workflow_updated_event
    after_destroy_commit :emit_workflow_deleted_event
  end

  class_methods do
    def workflow_event_key
      @workflow_event_key ||= Workflows::Catalog.key_for(name) ||
                              raise("#{name} is not in Workflows::Catalog::RECORD_MODELS")
    end
  end

  private

  def emit_workflow_created_event
    Workflows::Events.publish("#{self.class.workflow_event_key}.created", subject: self)
  end

  def emit_workflow_updated_event
    changes = saved_changes.keys - IGNORED_CHANGE_KEYS
    return if changes.empty?

    Workflows::Events.publish("#{self.class.workflow_event_key}.updated",
                              subject: self, payload: { "changes" => changes })
  end

  def emit_workflow_deleted_event
    snapshot = attributes.slice(*SNAPSHOT_KEYS).compact
    Workflows::Events.publish("#{self.class.workflow_event_key}.deleted",
                              subject: self, payload: { "subject_snapshot" => snapshot })
  end
end
