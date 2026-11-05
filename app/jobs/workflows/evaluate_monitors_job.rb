# typed: true

module Workflows
  # Event-driven monitor evaluation: when a monitored model's record changes,
  # re-check every monitor watching that model against that one subject.
  class EvaluateMonitorsJob < ApplicationJob
    extend T::Sig

    queue_as :workflows

    sig { params(household_id: String, subject_type: String, subject_id: String).void }
    def perform(household_id, subject_type, subject_id)
      household = Household.find_by(id: household_id)
      return unless household

      Current.set(household: household) do
        subject = subject_type.safe_constantize&.find_by(id: subject_id)
        next if subject.nil?

        Workflow.active.for_trigger(Catalog::MONITOR_TRIGGER).each do |workflow|
          monitor = Monitor.new(workflow)
          next unless monitor.subject_class_name == subject_type

          monitor.check(subject)
        end
      end
    end
  end
end
