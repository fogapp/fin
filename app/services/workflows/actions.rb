# typed: strict

module Workflows
  # Action dispatch for workflow steps. Data-mutation actions delegate to the
  # existing Workflows::Actions data-action classes (savepoint isolation and result
  # shapes included); side-effect actions (notify, webhook, fog_event,
  # create_issue, trigger_sync, run_workflow) register here directly.
  module Actions
    extend T::Sig

    DATA_ACTIONS = T.let([
      ActionType::AssignMerchant, ActionType::AssignCategory, ActionType::AssignAccount,
      ActionType::AddTag, ActionType::SetMemo, ActionType::SetLoan,
      ActionType::MarkAsTransfer, ActionType::TransferToAccount
    ].freeze, T::Array[ActionType])

    # Side-effect handlers, resolved lazily so autoloading works.
    SIDE_EFFECT_ACTIONS = T.let({
      ActionType::Notify      => "Workflows::Actions::Notify",
      ActionType::Webhook     => "Workflows::Actions::Webhook",
      ActionType::FogEvent    => "Workflows::Actions::FogEvent",
      ActionType::CreateIssue => "Workflows::Actions::CreateIssue",
      ActionType::TriggerSync => "Workflows::Actions::TriggerSync",
      ActionType::RunWorkflow => "Workflows::Actions::RunWorkflow"
    }.freeze, T::Hash[ActionType, String])

    # The step-config `params` keys each action reads, in permit-list form —
    # the allowlist the workflows API stores (anything else is dropped).
    # Keep in step with ActionExecutor::PARAM_BUILDERS and the side-effect
    # handlers; spec/services/workflows/actions_spec.rb checks every type
    # has an entry.
    PARAM_KEYS = T.let({
      ActionType::AssignMerchant    => [ :merchant_id ],
      ActionType::AssignCategory    => [ :category_id ],
      ActionType::AssignAccount     => [ :account_id ],
      # Scalar or array (the bulk path and migrated rule data store arrays).
      ActionType::AddTag            => [ :tag_id, { tag_id: [] } ],
      ActionType::SetMemo           => [ :value ],
      ActionType::SetLoan           => [ :loan_id ],
      ActionType::MarkAsTransfer    => [],
      ActionType::TransferToAccount => [ :account_id ],
      ActionType::Notify            => [ :title, :body, :severity, :href ],
      ActionType::Webhook           => [ :url ],
      ActionType::FogEvent          => [ :type, :title, :body, :key, :href, :severity ],
      ActionType::CreateIssue       => [ :title, :body, :severity ],
      ActionType::TriggerSync       => [ :target ],
      ActionType::RunWorkflow       => [ :workflow_id ]
    }.freeze, T::Hash[ActionType, T::Array[T.untyped]])

    # Permit-list for an action step's params; an unknown type permits none.
    sig { params(action_type: String).returns(T::Array[T.untyped]) }
    def self.param_keys(action_type)
      type = ActionType.try_deserialize(action_type)
      type ? PARAM_KEYS.fetch(type, []) : []
    end

    sig { returns(T::Array[ActionType]) }
    def self.action_types
      DATA_ACTIONS + SIDE_EFFECT_ACTIONS.keys
    end

    # `action_type` arrives as the raw string from step config JSON; the
    # unknown-type error result (not an exception) is part of the action
    # result protocol, so deserialization failure maps to it here.
    sig do
      params(action_type: String, params: T::Hash[T.untyped, T.untyped],
             run: WorkflowRun, subject: T.untyped)
        .returns(T::Hash[Symbol, T.untyped])
    end
    def self.execute(action_type, params, run:, subject:)
      type = ActionType.try_deserialize(action_type)
      return { status: :error, error: "Unknown action type: #{action_type}" } if type.nil?

      if DATA_ACTIONS.include?(type)
        return { status: :skipped, reason: "subject no longer exists" } if subject.nil?

        attrs_before = subject.attributes.dup
        tags_before  = subject.respond_to?(:tag_ids) ? subject.tag_ids.sort : nil

        result = ActionExecutor.new(resource: subject).execute(type.serialize, params.deep_stringify_keys)
        if result[:status] == :applied
          undo = change_delta(subject, attrs_before, tags_before)
          result = result.merge(undo: undo) if undo.any?
        end
        result
      else
        handler_class = SIDE_EFFECT_ACTIONS.fetch(type)
        handler_class.constantize.new.call(params.deep_stringify_keys, run: run, subject: subject)
      end
    rescue => e
      { status: :error, error: "#{e.class}: #{e.message}" }
    end

    # The undo record a revert restores from:
    # {"attr" => [before, after], "tag_ids" => [[..], [..]]}. Attributes are diffed around the action
    # (instance-safe even when several steps save the same subject); tag
    # mutations happen through the association, so they are diffed
    # explicitly.
    sig do
      params(subject: T.untyped, attrs_before: T::Hash[String, T.untyped],
             tags_before: T.nilable(T::Array[T.untyped])).returns(T::Hash[String, T.untyped])
    end
    def self.change_delta(subject, attrs_before, tags_before)
      changes = {}
      subject.attributes.each do |attr, after|
        next if %w[updated_at created_at].include?(attr)

        before = attrs_before[attr]
        changes[attr] = [ before, after ] if before != after
      end
      if tags_before
        # Tag actions write join rows directly; reset the cached association
        # before diffing.
        subject.tags.reset
        tags_after = subject.tag_ids.sort
        changes["tag_ids"] = [ tags_before, tags_after ] if tags_after != tags_before
      end
      changes
    end
  end
end
