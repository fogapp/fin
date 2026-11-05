# typed: strict

module Workflows
  module Actions
    # POSTs a JSON snapshot of the event to a workflow-configured URL so
    # external systems (Home Assistant, ntfy, relays) can react.
    class Webhook
      extend T::Sig

      sig do
        params(params: T::Hash[String, T.untyped], run: WorkflowRun, subject: T.untyped)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def call(params, run:, subject:)
        url = params["url"].to_s
        return { status: :error, error: "webhook url is required" } if url.blank?

        payload = {
          event_type:    run.event_type,
          workflow:      run.workflow&.name,
          run_id:        run.id,
          subject_type:  run.subject_type,
          subject_id:    run.subject_id,
          event_payload: run.event_payload,
          subject:       subject_snapshot(subject)
        }

        response = WebhookDelivery.post(url, payload)
        status = response[:status] == "delivered" ? :applied : :error
        { status: status, code: response[:code] }
      rescue => e
        { status: :error, error: e.message }
      end

      private

      # Only catalog-whitelisted fields leave the app.
      sig { params(subject: T.untyped).returns(T::Hash[String, T.untyped]) }
      def subject_snapshot(subject)
        return {} if subject.nil?

        Catalog.fields_for(subject.class.name).keys
               .select { |field| subject.respond_to?(field) }
               .index_with { |field| subject.public_send(field) }
      end
    end
  end
end
