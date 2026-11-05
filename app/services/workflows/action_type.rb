# typed: strict

module Workflows
  # Every action a workflow step can execute. Data actions mutate the run's
  # subject through the Workflows::Actions data-action classes; side-effect actions fan
  # out to handlers under Workflows::Actions::*. Step configs store the
  # serialized value in config["action_type"] — deserialize at the boundary
  # (Workflows::Actions.execute) rather than in the JSON itself.
  class ActionType < T::Enum
    include ApplicationEnum

    enums do
      # Data actions (subject mutations, revertible via change deltas)
      AssignMerchant = new("assign_merchant")
      AssignCategory = new("assign_category")
      AssignAccount = new("assign_account")
      AddTag = new("add_tag")
      SetMemo = new("set_memo")
      SetLoan = new("set_loan")
      MarkAsTransfer = new("mark_as_transfer")
      TransferToAccount = new("transfer_to_account")

      # Side-effect actions (not revertible)
      Notify = new("notify")
      Webhook = new("webhook")
      FogEvent = new("fog_event")
      CreateIssue = new("create_issue")
      TriggerSync = new("trigger_sync")
      RunWorkflow = new("run_workflow")
    end
  end
end
