# typed: strict

module Workflows
  module Actions
    # Creates an in-app Notification and, when the household has a
    # notification webhook configured (e.g. an ntfy topic), POSTs the
    # message there too. On fog the Notification also reaches the household
    # event stream as `fin.notification` (Notification's after-commit hook),
    # so it is published from every path that notifies, not just this one.
    class Notify
      extend T::Sig

      sig do
        params(params: T::Hash[String, T.untyped], run: WorkflowRun, subject: T.untyped)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def call(params, run:, subject:)
        title = Template.render(params["title"].presence || "Workflow notification", run: run, subject: subject)
        body  = Template.render(params["body"], run: run, subject: subject)
        severity = Severity.try_deserialize(params["severity"].to_s) || Severity::Info
        # In-app destination; template-rendered so a payload key can carry it
        # (e.g. "/review?month={{month}}").
        href = Template.render(params["href"], run: run, subject: subject).presence

        notification = Notification.create!(
          household_id: run.household_id,
          title:        title,
          body:         body.presence,
          severity:     severity,
          href:         href,
          subject_type: run.subject_type,
          subject_id:   run.subject_id,
          workflow_run: run
        )

        webhook_result = deliver_webhook(run, title, body, severity)

        { status: :applied, notification_id: notification.id }.merge(webhook_result)
      end

      private

      sig do
        params(run: WorkflowRun, title: String, body: String, severity: Severity)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def deliver_webhook(run, title, body, severity)
        url = run.household&.notification_webhook_url
        return {} if url.blank?

        response = WebhookDelivery.post(url, {
          title: title, body: body, severity: severity,
          workflow: run.workflow&.name, event_type: run.event_type
        })
        { webhook_status: response[:status], webhook_code: response[:code] }
      rescue => e
        { webhook_status: "error", webhook_error: e.message }
      end
    end
  end
end
