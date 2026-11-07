# typed: strict

module Workflows
  # Walks a run through its workflow's step tree.
  #
  # Semantics:
  # - Sibling `branch` steps at one level form a single if/elsif chain in
  #   position order; the first match wins, an `else: true` branch matches
  #   when none before it did. Children of the matching branch execute.
  # - `action` steps execute in order via Workflows::Actions.
  # - A `wait` step parks the run and schedules a resume; its children run
  #   after the delay against the reloaded subject. Anything positioned
  #   after a wait step is unreachable by design — the builder keeps waits
  #   last among their siblings.
  class Executor
    extend T::Sig

    MAX_CHAIN_DEPTH = T.let(5, Integer)

    sig { params(run: WorkflowRun).void }
    def initialize(run)
      @run = run
      @workflow = T.let(T.must(run.workflow), Workflow)
    end

    sig { params(resume_from_step_id: T.nilable(String)).void }
    def call(resume_from_step_id: nil)
      return unless resumable_status?

      if @run.ancestor_workflow_ids.include?(@run.workflow_id)
        return finish!(WorkflowRun::Status::Cancelled, error: "workflow cycle detected in run chain")
      end
      if @run.chain_depth >= MAX_CHAIN_DEPTH
        return finish!(WorkflowRun::Status::Cancelled, error: "run chain exceeded depth #{MAX_CHAIN_DEPTH}")
      end

      subject = load_subject
      # Deleted-record events and schedule-triggered runs are legitimately
      # subject-less; anything else losing its subject means the record went
      # away between dispatch and execution.
      subjectless_ok = @run.event_type.end_with?(".deleted") || @run.subject_type.nil?
      if subject.nil? && !subjectless_ok
        return finish!(WorkflowRun::Status::Cancelled, error: "subject no longer exists")
      end

      @run.update!(status: WorkflowRun::Status::Running, started_at: @run.started_at || Time.current)

      steps = if resume_from_step_id
        WorkflowStep.where(workflow_id: @workflow.id, parent_id: resume_from_step_id).order(:position).to_a
      else
        @workflow.root_steps.to_a
      end

      outcome = execute_level(steps, subject)
      return if outcome == :parked

      if discard_noop_run?
        @run.destroy!
      else
        finish!(WorkflowRun::Status::Completed)
      end
    rescue => e
      finish!(WorkflowRun::Status::Failed, error: "#{e.class}: #{e.message}")
      publish_run_failed
    end

    private

    sig { returns(T::Boolean) }
    def resumable_status?
      WorkflowRun::UNFINISHED_STATUSES.include?(@run.status)
    end

    sig { returns(T.untyped) }
    def load_subject
      return nil if @run.subject_type.blank?

      klass = @run.subject_type&.safe_constantize
      klass&.find_by(id: @run.subject_id)
    end

    sig { params(steps: T::Array[WorkflowStep], subject: T.untyped).returns(Symbol) }
    def execute_level(steps, subject)
      branch_taken = T.let(false, T::Boolean)

      steps.each do |step|
        case step.kind
        when WorkflowStep::Kind::Branch
          if branch_taken
            record(step, WorkflowRunStep::Status::Skipped, output: { reason: "earlier branch matched" })
            next
          end

          if branch_matches?(step, subject)
            branch_taken = true
            record(step, WorkflowRunStep::Status::Matched)
            outcome = execute_level(step.children.to_a, subject)
            return outcome unless outcome == :done
          else
            record(step, WorkflowRunStep::Status::NotMatched)
          end
        when WorkflowStep::Kind::Action
          result = execute_action(step, subject)
          if result[:status].to_s == "error" && step.config["stop_on_error"] == true
            return :halted
          end
        when WorkflowStep::Kind::Wait
          park!(step)
          return :parked
        end
      end

      :done
    end

    sig { params(step: WorkflowStep, subject: T.untyped).returns(T::Boolean) }
    def branch_matches?(step, subject)
      return true if step.else_branch?

      ConditionCheck.match?(subject, step.conditions, match_all: step.match_all?)
    end

    sig { params(step: WorkflowStep, subject: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def execute_action(step, subject)
      result = Actions.execute(
        step.config["action_type"].to_s,
        step.config.fetch("params", {}),
        run:     @run,
        subject: subject
      )
      # The action-result protocol speaks in symbols (:applied/:skipped/
      # :error); an out-of-vocabulary status raises here, failing the run —
      # same outcome the old inclusion validation gave.
      record(step, WorkflowRunStep::Status.deserialize(result[:status].to_s),
             output: result.except(:status))
      result
    end

    sig { params(step: WorkflowStep).void }
    def park!(step)
      resume_at = step.config["duration_seconds"].to_i.seconds.from_now
      record(step, WorkflowRunStep::Status::Waiting, resume_at: resume_at)
      @run.update!(status: WorkflowRun::Status::Waiting, cursor_step_id: step.id)
      ExecuteRunJob.set(wait_until: resume_at).perform_later(@run.id, resume_from_step_id: step.id)
    end

    sig do
      params(step: WorkflowStep, status: WorkflowRunStep::Status,
             output: T::Hash[T.untyped, T.untyped], resume_at: T.untyped).void
    end
    def record(step, status, output: {}, resume_at: nil)
      @run.run_steps.create!(workflow_step: step, status: status, output: output, resume_at: resume_at)
    end

    sig { params(status: WorkflowRun::Status, error: T.nilable(String)).void }
    def finish!(status, error: nil)
      @run.update!(status: status, error: error, finished_at: Time.current)
      record_activity(status)
    end

    sig { returns(LogLevel) }
    def log_level
      @log_level ||= T.let(@run.household&.workflow_log_level || LogLevel::Info,
                           T.nilable(LogLevel))
    end

    # At log level none, a completed run that changed nothing is telemetry,
    # not history — it is dropped entirely rather than finished. Runs that
    # applied an action (revert data), hit an action error, or parked a wait
    # are always kept; failed and cancelled runs never reach this check.
    sig { returns(T::Boolean) }
    def discard_noop_run?
      return false unless log_level == LogLevel::None

      !@run.run_steps.where(status: [
        WorkflowRunStep::Status::Applied,
        WorkflowRunStep::Status::Error,
        WorkflowRunStep::Status::Waiting
      ]).exists?
    end

    # Debug logs every finish (the old behavior); info skips the entry for
    # completed runs that neither applied an action nor hit one erroring;
    # none logs failures only. Failures are always recorded at every level.
    sig { params(status: WorkflowRun::Status).returns(T::Boolean) }
    def activity_worthy?(status)
      case log_level
      when LogLevel::Debug then true
      when LogLevel::None  then status == WorkflowRun::Status::Failed
      else
        status != WorkflowRun::Status::Completed ||
          @run.run_steps.where(status: [
            WorkflowRunStep::Status::Applied, WorkflowRunStep::Status::Error
          ]).exists?
      end
    end

    sig { params(status: WorkflowRun::Status).void }
    def record_activity(status)
      return unless activity_worthy?(status)

      duration_ms = @run.started_at && ((Time.current - @run.started_at) * 1000)
      Activity.record(
        source:      "workflow",
        event:       "run.#{status}",
        severity:    status == WorkflowRun::Status::Failed ? Severity::Error : Severity::Info,
        summary:     "Workflow \"#{@workflow.name}\" #{status} (#{@run.event_type})#{@run.error ? ": #{@run.error}" : ''}",
        subject:     @run.subject_type.present? ? load_subject : nil,
        caused_by:   @run,
        payload:     { workflow_id: @workflow.id, run_id: @run.id, event_type: @run.event_type },
        duration_ms: duration_ms,
        household_id: @run.household_id
      )
    end

    sig { void }
    def publish_run_failed
      # Meta-event so users can alert on broken automations. Never re-enter
      # for failures of run-failed workflows themselves.
      return if @run.event_type == "workflow.run_failed"

      Events.publish("workflow.run_failed", subject: @run,
                     payload: { "workflow_name" => @workflow.name, "error" => @run.error })
    end
  end
end
