# typed: strict

module Workflows
  module Actions
    # Raises an Issue with templated title/body — the workflow-native way to
    # say "a human should look at this".
    class CreateIssue
      extend T::Sig

      sig do
        params(params: T::Hash[String, T.untyped], run: WorkflowRun, subject: T.untyped)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def call(params, run:, subject:)
        title = Template.render(params["title"], run: run, subject: subject)
        return { status: :error, error: "issue title is required" } if title.blank?

        severity = Severity.try_deserialize(params["severity"].to_s) || Severity::Warning

        issue = Issue.raise_once!(
          key:      "workflow:#{run.workflow_id}:#{run.subject_type}:#{run.subject_id}",
          title:    title,
          body:     Template.render(params["body"], run: run, subject: subject),
          severity: severity,
          source:   "workflow:#{run.workflow_id}"
        )

        if issue
          { status: :applied, issue_id: issue.id }
        else
          { status: :skipped, reason: "concurrent write raised the same issue" }
        end
      end
    end
  end
end
