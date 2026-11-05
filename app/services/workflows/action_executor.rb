# typed: strict

module Workflows
  class ActionExecutor < T::Struct
    ACTION_CLASSES = T.let({
      "assign_merchant"  => Actions::AssignMerchant,
      "assign_category"  => Actions::AssignCategory,
      "assign_account"   => Actions::AssignAccount,
      "add_tag"          => Actions::AddTag,
      "set_memo"         => Actions::SetMemo,
      "mark_as_transfer" => Actions::MarkAsTransfer,
      "transfer_to_account" => Actions::TransferToAccount,
      "set_loan"         => Actions::SetLoan
    }.freeze, T::Hash[String, T.untyped])

    PARAM_BUILDERS = T.let({
      "assign_merchant"  => ->(p) { { merchant_id: p["merchant_id"] } },
      "assign_category"  => ->(p) { { category_id: p["category_id"] } },
      "assign_account"   => ->(p) { { account_id: p["account_id"] } },
      "add_tag"          => ->(p) { { tag_id: p["tag_id"] } },
      "set_memo"         => ->(p) { { value: p["value"].to_s } },
      "mark_as_transfer" => ->(_p) { {} },
      "transfer_to_account" => ->(p) { { account_id: p["account_id"] } },
      "set_loan"         => ->(p) { { loan_id: p["loan_id"] } }
    }.freeze, T::Hash[String, T.untyped])

    const :resource, T.untyped
    const :dry_run, T::Boolean, default: false

    # Runs one data action against the resource. Every failure (unknown
    # type, bad params, DB error) comes back as an :error result rather than
    # an exception, per the action-result protocol.
    sig { params(action_type: String, params: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def execute(action_type, params)
      klass   = ACTION_CLASSES[action_type]
      builder = PARAM_BUILDERS[action_type]
      return { status: :error, error: "Unknown action type: #{action_type}", action_type: action_type } unless klass && builder

      # Savepoint isolates DB-level errors (e.g. FK violations) so a failed
      # action doesn't abort the workflow run's outer transaction.
      result = ActiveRecord::Base.transaction(requires_new: true) do
        klass.new(**builder.call(params)).execute(resource, dry_run: dry_run)
      end
      result.merge(action_type: action_type)
    rescue => e
      { status: :error, error: e.message, action_type: action_type }
    end
  end
end
