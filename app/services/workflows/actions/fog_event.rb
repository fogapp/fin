# typed: strict

module Workflows
  module Actions
    # Publishes a structured event to fog's household event stream, where a
    # reader such as HUD routes it by type: `fin.<type>`, the type defaulting
    # to the event that triggered the run (`fin.budget.category_exceeded`) or,
    # for schedule and monitor runs, the workflow's name. Off fog the step is
    # skipped.
    #
    # The data carries what an ntfy push from `notify` would — templated title
    # and body, severity, workflow and event — plus ids, never a subject
    # snapshot: amounts and balances leave only when a user templates them in.
    class FogEvent
      extend T::Sig

      # Triggers whose event type says nothing about what happened.
      GENERIC_EVENT_TYPES = T.let(%w[schedule.fired monitor.triggered].freeze, T::Array[String])

      sig do
        params(params: T::Hash[String, T.untyped], run: WorkflowRun, subject: T.untyped)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def call(params, run:, subject:)
        return { status: :skipped, reason: "not running on fog" } unless FogEvents.available?

        workflow_name = run.workflow&.name
        type = FogEvents.type_for(params["type"].presence || default_type(run, workflow_name))
        title = Template.render(params["title"].presence || workflow_name || "Workflow event", run: run, subject: subject)
        body = Template.render(params["body"], run: run, subject: subject).presence
        key = Template.render(params["key"], run: run, subject: subject).presence
        severity = Severity.try_deserialize(params["severity"].to_s) || Severity::Info
        # A step runs once per run; the digest tells two of them in one run
        # apart, and a re-executed step republishes under the same id.
        id = FogEvents.event_id("run", run.id, Digest::SHA256.hexdigest([ type, title, body, key ].join("\0")).first(16))

        outcome = FogEvents.publish(type: type, id: id, subject: workflow_name || title, household_id: run.household_id, data: {
          "title" => title, "body" => body, "key" => key,
          "link" => FogEvents.link(Template.render(params["href"], run: run, subject: subject).presence),
          "severity" => severity.serialize, "workflow" => workflow_name, "workflow_id" => run.workflow_id,
          "event_type" => run.event_type, "run_id" => run.id,
          "subject_type" => run.subject_type, "subject_id" => run.subject_id
        }.compact)

        case outcome
        when FogEvents::Outcome::Published then { status: :applied, type: type, event_id: id }
        when FogEvents::Outcome::Unavailable then { status: :skipped, reason: "not running on fog" }
        else { status: :error, error: "fog did not accept the event", type: type }
        end
      end

      private

      sig { params(run: WorkflowRun, workflow_name: T.nilable(String)).returns(String) }
      def default_type(run, workflow_name)
        return run.event_type unless GENERIC_EVENT_TYPES.include?(run.event_type)

        workflow_name.presence || run.event_type
      end
    end
  end
end
