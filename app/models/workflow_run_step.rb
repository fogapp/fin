# typed: true

class WorkflowRunStep < ApplicationRecord
  # Per-step outcomes recorded by Workflows::Executor: branch evaluation
  # (matched/not_matched/skipped), action results (applied/skipped/error),
  # and parked wait steps (waiting).
  class Status < T::Enum
    include ApplicationEnum

    enums do
      Matched = new("matched")
      NotMatched = new("not_matched")
      Applied = new("applied")
      Skipped = new("skipped")
      Error = new("error")
      Waiting = new("waiting")
    end
  end

  typed_enum :status, Status

  belongs_to :workflow_run
  belongs_to :workflow_step, optional: true
end
