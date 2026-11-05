# typed: true

module Workflows
  class ExecuteRunJob < ApplicationJob
    extend T::Sig

    queue_as :workflows

    sig { params(run_id: String, resume_from_step_id: T.nilable(String)).void }
    def perform(run_id, resume_from_step_id: nil)
      with_record(WorkflowRun, run_id) do |run|
        Executor.new(run).call(resume_from_step_id: resume_from_step_id)
      end
    end
  end
end
