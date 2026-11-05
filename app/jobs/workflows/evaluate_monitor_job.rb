# typed: true

module Workflows
  # Manual "run now" for a monitor workflow: evaluate its subject scope
  # immediately instead of waiting for the next sweep. Edge semantics are
  # unchanged — subjects already in the triggered state don't re-fire.
  class EvaluateMonitorJob < ApplicationJob
    extend T::Sig

    queue_as :workflows
    limits_concurrency to: 1, key: ->(workflow_id) { workflow_id }

    sig { params(workflow_id: String).void }
    def perform(workflow_id)
      with_record(Workflow, workflow_id) do |workflow|
        next unless workflow.trigger_type == Catalog::MONITOR_TRIGGER

        checked = Monitor.new(workflow).sweep!
        Rails.logger.info("[Workflows::EvaluateMonitorJob] workflow=#{workflow.id} checked=#{checked}")
      end
    end
  end
end
