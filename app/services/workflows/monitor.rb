# typed: strict

module Workflows
  # Evaluates a monitor workflow (trigger_type "monitor") against a subject
  # and fires a run only on the false→true edge, tracked per
  # (workflow, subject) in workflow_monitor_states.
  #
  # trigger_config shape:
  #   { "subject"    => "account",              # Workflows::Catalog::RECORD_MODELS key
  #     "match_all"  => true,
  #     "conditions" => [{ "field" => "balance_usd", "operator" => "less_than", "value" => "500" }] }
  class Monitor
    extend T::Sig

    sig { params(workflow: Workflow).void }
    def initialize(workflow)
      @workflow = T.let(workflow, Workflow)
    end

    sig { returns(T.nilable(String)) }
    def subject_class_name
      Catalog::RECORD_MODELS[@workflow.trigger_config["subject"].to_s]
    end

    sig { params(subject: T.untyped).returns(T::Boolean) }
    def evaluate(subject)
      ConditionCheck.match?(subject, conditions, match_all: match_all?)
    end

    # One full evaluation pass over the subject table. When every condition
    # translates to SQL (and semantics are AND), the walk covers only
    # currently-matching rows: rising edges come from checking those, and
    # falling edges are recorded set-wise by flipping stale true states whose
    # subjects no longer match — without instantiating the rest of the table
    # (the sweep used to batch-load and Ruby-evaluate entire tables every 15
    # minutes). Falls back to the full walk when any condition needs the Ruby
    # evaluator, or under OR semantics where partially-applied SQL would drop
    # rows that match only an untranslated condition. Returns the number of
    # subjects checked, for logging.
    sig { returns(Integer) }
    def sweep!
      scope = subjects
      return 0 if scope.nil?

      narrowed = matching_scope(scope)
      walk     = narrowed || scope

      checked = 0
      walk.find_in_batches(batch_size: 500) do |batch|
        check_batch(batch)
        checked += batch.size
      end
      reset_departed!(scope, narrowed) if narrowed
      checked
    end

    # Evaluate a batch of subjects with one state lookup instead of a
    # find_or_initialize_by per row (the 15-minute sweep walks whole tables).
    sig { params(subjects: T::Array[T.untyped]).void }
    def check_batch(subjects)
      return if subjects.empty?

      states = WorkflowMonitorState.where(
        workflow_id:  @workflow.id,
        subject_type: subjects.first.class.name,
        subject_id:   subjects.map(&:id)
      ).index_by(&:subject_id)

      subjects.each do |subject|
        state = states[subject.id] || WorkflowMonitorState.new(
          workflow_id:  @workflow.id,
          subject_type: subject.class.name,
          subject_id:   subject.id
        )
        check(subject, state: state)
      end
    end

    # Evaluate against one subject and fire on the rising edge. Returns the
    # created run, if any.
    sig { params(subject: T.untyped, state: T.nilable(WorkflowMonitorState)).returns(T.nilable(WorkflowRun)) }
    def check(subject, state: nil)
      state ||= WorkflowMonitorState.find_or_initialize_by(
        workflow_id:  @workflow.id,
        subject_type: subject.class.name,
        subject_id:   subject.id
      )
      previous = state.persisted? ? state.result : false
      current  = evaluate(subject)

      # Write only when the result flips (or the state is new) — the sweep
      # re-evaluates entire tables every 15 minutes, and an unconditional
      # update! turned every sweep into table_size UPDATEs.
      # last_evaluated_at therefore records the last state *change*, not the
      # last evaluation; nothing reads it per-evaluation.
      if !state.persisted? || state.result != current
        state.update!(result: current, last_evaluated_at: Time.current)
      end
      return nil unless current && !previous

      run = @workflow.runs.create!(
        household_id:  @workflow.household_id,
        subject_type:  subject.class.name,
        subject_id:    subject.id,
        event_type:    "monitor.triggered",
        event_payload: { "conditions" => @workflow.trigger_config["conditions"] },
        status:        WorkflowRun::Status::Pending
      )
      ExecuteRunJob.perform_later(run.id)
      run
    rescue ActiveRecord::RecordNotUnique
      nil # concurrent evaluation of the same (workflow, subject) — one wins
    end

    # All subjects this monitor watches (household-scoped via default scopes).
    sig { returns(T.untyped) }
    def subjects
      klass = subject_class_name&.safe_constantize
      klass&.all
    end

    private

    sig { returns(T::Array[WorkflowStep::Condition]) }
    def conditions
      Array(@workflow.trigger_config["conditions"]).map do |c|
        WorkflowStep::Condition.new(c["field"].to_s, c["operator"].to_s, c["value"].to_s)
      end
    end

    sig { returns(T::Boolean) }
    def match_all?
      @workflow.trigger_config.fetch("match_all", true) != false
    end

    # The SQL-narrowed "currently matching" scope, or nil when narrowing
    # can't be exact: under AND semantics with every condition translated,
    # the narrowed set IS the true set (check still re-evaluates each row in
    # Ruby, so SQL/Ruby edge-case disagreements can only suppress a fire,
    # never invent one).
    sig { params(scope: T.untyped).returns(T.nilable(T.untyped)) }
    def matching_scope(scope)
      return nil unless match_all?

      narrowed, ruby_conditions = Conditions::SqlTranslator
        .new(conditions, scope.klass, match_all: true)
        .apply(scope)
      ruby_conditions.empty? ? narrowed : nil
    end

    # Subjects that previously matched but are absent from the narrowed set
    # re-evaluate to false without being instantiated: flip their states so
    # the next rise is an edge again. Mirrors check()'s write-on-flip (no
    # run fires on a fall).
    sig { params(scope: T.untyped, narrowed: T.untyped).void }
    def reset_departed!(scope, narrowed)
      WorkflowMonitorState
        .where(workflow_id: @workflow.id, subject_type: scope.klass.name, result: true)
        .where.not(subject_id: narrowed.select(:id))
        .update_all(result: false, last_evaluated_at: Time.current, updated_at: Time.current)
    end
  end
end
