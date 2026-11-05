# typed: strict

module Workflows
  # Undoes the data mutations a workflow run made to its subject, from the
  # change deltas captured at execution time ({attr => [before, after]} on
  # each applied action step).
  #
  # Reverts are three-way: an attribute is only restored to `before` when it
  # still holds the recorded `after` — values the user (or a later workflow)
  # changed since are left alone and counted as conflicts. Tag deltas revert
  # by removing the tags the run added (manual additions survive). Side
  # effects (notifications, webhooks) are not undoable and are ignored.
  #
  # Event publishing is suppressed while writing — restoring old values must
  # not re-trigger the very workflow being reverted.
  module Revert
    extend T::Sig

    Result = Struct.new(:reverted, :conflicted, :skipped, keyword_init: true)

    sig { params(run: WorkflowRun, record_activity: T::Boolean).returns(Result) }
    def self.call(run, record_activity: true)
      result = Result.new(reverted: 0, conflicted: 0, skipped: 0)
      return result if run.reverted_at.present?

      subject = run.subject_type&.safe_constantize&.find_by(id: run.subject_id)
      steps = revertible_steps(run)

      if subject.nil? || steps.empty?
        result.skipped += 1
        run.update!(reverted_at: Time.current) if steps.any?
        return result
      end

      Events.suppress do
        # Newest step first: layered writes unwind in reverse order.
        steps.reverse_each do |step|
          revert_step(subject, step.output["undo"], result)
        end
        subject.save! if subject.changed?
      end

      run.update!(reverted_at: Time.current)
      record(run, result) if record_activity
      result
    end

    sig { params(run: WorkflowRun).returns(T::Array[WorkflowRunStep]) }
    def self.revertible_steps(run)
      run.run_steps
         .where(status: WorkflowRunStep::Status::Applied)
         .order(:created_at)
         .select { |step| step.output.is_a?(Hash) && step.output["undo"].present? }
    end

    sig { params(subject: T.untyped, changes: T::Hash[String, T.untyped], result: T.untyped).void }
    def self.revert_step(subject, changes, result)
      changes.each do |attr, (before, after)|
        if attr == "tag_ids"
          revert_tags(subject, before, after, result)
        elsif subject.respond_to?(:"#{attr}=") && subject.has_attribute?(attr)
          current = subject.public_send(attr)
          current = normalize(current)
          if current == normalize(after)
            subject.public_send(:"#{attr}=", before)
            result.reverted += 1
          else
            result.conflicted += 1
          end
        else
          result.skipped += 1
        end
      end
    end
    private_class_method :revert_step

    # Remove only the tags this run added and that are still present.
    sig { params(subject: T.untyped, before: T::Array[T.untyped], after: T::Array[T.untyped], result: T.untyped).void }
    def self.revert_tags(subject, before, after, result)
      added = after - before
      removable = subject.tag_ids & added
      if removable.any?
        subject.tag_ids = subject.tag_ids - removable
        result.reverted += 1
      else
        result.conflicted += 1
      end
    end
    private_class_method :revert_tags

    # JSON round-trips turn dates/times/decimals into strings; compare in
    # the same representation the delta was stored in.
    sig { params(value: T.untyped).returns(T.untyped) }
    def self.normalize(value)
      case value
      when Time, Date, DateTime then value.as_json
      when BigDecimal then value.to_s("F")
      else value
      end
    end
    private_class_method :normalize

    sig { params(run: WorkflowRun, result: T.untyped).void }
    def self.record(run, result)
      Activity.record(
        source: "workflow", event: "run.reverted",
        summary: "Reverted workflow run: #{result.reverted} change#{result.reverted == 1 ? '' : 's'} restored" \
                 "#{result.conflicted.positive? ? ", #{result.conflicted} kept (changed since)" : ''}",
        subject: run,
        payload: { workflow_id: run.workflow_id, reverted: result.reverted,
                   conflicted: result.conflicted, skipped: result.skipped },
        household_id: run.household_id
      )
    end
    private_class_method :record
  end
end
