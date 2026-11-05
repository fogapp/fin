require "rails_helper"

RSpec.describe Workflows::Actions do
  let(:account)  { create(:account) }
  let(:txn)      { create(:cash_transaction, :bank, account: account, description: "STARBUCKS #12", amount: -5.25) }
  let(:workflow) { create(:workflow, name: "Coffee watcher") }
  let(:run) do
    create(:workflow_run, workflow: workflow,
           subject_type: "CashTransaction", subject_id: txn.id,
           event_type: "cash_transaction.created")
  end

  def execute(action_type, params)
    described_class.execute(action_type, params, run: run, subject: txn)
  end

  describe "notify" do
    it "creates an in-app notification with templated title/body" do
      result = execute("notify", {
        "title" => "{{description}} posted",
        "body" => "Amount {{amount}} via {{workflow_name}}",
        "severity" => "warning"
      })

      expect(result[:status]).to eq(:applied)
      notification = Notification.find(result[:notification_id])
      expect(notification.title).to eq("STARBUCKS #12 posted")
      expect(notification.body).to eq("Amount -5.25 via Coffee watcher")
      expect(notification.severity).to eq(Severity::Warning)
      expect(notification.subject_id).to eq(txn.id)
    end

    it "posts to the household webhook when configured" do
      Current.household.update!(notification_webhook_url: "https://ntfy.example/topic")
      allow(Workflows::WebhookDelivery).to receive(:post).and_return({ status: "delivered", code: 200 })

      result = execute("notify", { "title" => "hi" })

      expect(Workflows::WebhookDelivery).to have_received(:post)
        .with("https://ntfy.example/topic", hash_including(title: "hi"))
      expect(result[:webhook_status]).to eq("delivered")
    end

    it "never renders non-catalog fields in templates" do
      result = execute("notify", { "title" => "x {{source_row_hash}} y" })
      expect(Notification.find(result[:notification_id]).title).to eq("x  y")
    end
  end

  describe "webhook" do
    it "delivers a catalog-whitelisted subject snapshot" do
      captured = nil
      allow(Workflows::WebhookDelivery).to receive(:post) { |_url, payload| captured = payload; { status: "delivered", code: 200 } }

      result = execute("webhook", { "url" => "https://example.com/hook" })

      expect(result[:status]).to eq(:applied)
      expect(captured[:subject]).to include("description" => "STARBUCKS #12")
      expect(captured[:subject]).not_to have_key("source_row_hash")
    end

    it "refuses non-https URLs" do
      result = execute("webhook", { "url" => "http://plain.example/hook" })
      expect(result[:status]).to eq(:error)
      expect(result[:error]).to match(/https/)
    end

    it "reports non-2xx responses as errors" do
      allow(Workflows::WebhookDelivery).to receive(:post).and_return({ status: "rejected", code: 500 })
      result = execute("webhook", { "url" => "https://example.com/hook" })
      expect(result[:status]).to eq(:error)
      expect(result[:code]).to eq(500)
    end
  end

  describe "fog_event" do
    let(:fog_env) { { "FOG_API_URL" => "http://fog.test", "FOG_API_TOKEN" => "apptok" } }

    it "publishes an event typed by the trigger, with templated fields and no subject snapshot" do
      stub_const("ENV", ENV.to_h.merge(fog_env, "FIN_WEBAUTHN_ORIGINS" => "https://fin.example.test"))
      posted = nil
      stub_request(:post, "http://fog.test/app/v1/events")
        .with(headers: { "Authorization" => "Bearer apptok", "Content-Type" => "application/json" })
        .to_return { |request| (posted = JSON.parse(request.body)) && { status: 202, body: "{}" } }

      result = execute("fog_event", {
        "title" => "{{description}} posted", "body" => "{{amount}}", "key" => "coffee-{{id}}",
        "href" => "/cashflow", "severity" => "warning"
      })

      expect(result).to include(status: :applied, type: "fin.cash_transaction.created")
      expect(posted).to include("specversion" => "1.0", "type" => "fin.cash_transaction.created",
                                "subject" => "Coffee watcher", "id" => result[:event_id])
      expect(posted["id"].length).to be <= 128
      expect(posted["data"]).to include(
        "title" => "STARBUCKS #12 posted", "body" => "-5.25", "key" => "coffee-#{txn.id}",
        "link" => "https://fin.example.test/cashflow", "severity" => "warning",
        "workflow" => "Coffee watcher", "event_type" => "cash_transaction.created", "run_id" => run.id,
        "subject_type" => "CashTransaction", "subject_id" => txn.id
      )
      expect(posted["data"]).not_to have_key("subject")
    end

    it "republishes under the same id, so fog absorbs a re-executed step" do
      stub_const("ENV", ENV.to_h.merge(fog_env))
      stub_request(:post, "http://fog.test/app/v1/events").to_return(status: 202)

      first = execute("fog_event", { "title" => "hi" })
      expect(execute("fog_event", { "title" => "hi" })[:event_id]).to eq(first[:event_id])
      expect(execute("fog_event", { "title" => "other" })[:event_id]).not_to eq(first[:event_id])
    end

    it "takes the type from params, folded into fog's alphabet" do
      stub_const("ENV", ENV.to_h.merge(fog_env))
      stub_request(:post, "http://fog.test/app/v1/events").to_return(status: 202)

      expect(execute("fog_event", { "type" => "Coffee Run" })[:type]).to eq("fin.coffee-run")
    end

    it "names a scheduled run's event after its workflow" do
      stub_const("ENV", ENV.to_h.merge(fog_env))
      stub_request(:post, "http://fog.test/app/v1/events").to_return(status: 202)
      run.update!(event_type: "schedule.fired", subject_type: nil, subject_id: nil)

      expect(described_class.execute("fog_event", {}, run: run, subject: nil)[:type]).to eq("fin.coffee-watcher")
    end

    it "is skipped off fog" do
      stub_const("ENV", ENV.to_h.except("FOG_API_URL", "FOG_API_TOKEN"))

      expect(execute("fog_event", { "title" => "hi" })).to eq(status: :skipped, reason: "not running on fog")
    end

    it "reports a refused event as a step error and records it" do
      stub_const("ENV", ENV.to_h.merge(fog_env))
      stub_request(:post, "http://fog.test/app/v1/events").to_return(status: 503)

      expect(execute("fog_event", { "title" => "hi" })[:status]).to eq(:error)
      expect(ActivityEntry.where(source: "fog", event: "event.failed")).to exist
    end
  end

  describe "notify on fog" do
    it "keeps the ntfy push and queues the notification for the event stream" do
      stub_const("ENV", ENV.to_h.merge("FOG_API_URL" => "http://fog.test", "FOG_API_TOKEN" => "apptok"))
      Current.household.update!(notification_webhook_url: "https://ntfy.example/topic")
      allow(Workflows::WebhookDelivery).to receive(:post).and_return({ status: "delivered", code: 200 })

      result = nil
      expect { result = execute("notify", { "title" => "hi" }) }
        .to have_enqueued_job(PublishNotificationEventJob).with(kind_of(String))
      expect(result).to include(status: :applied, webhook_status: "delivered")
    end
  end

  describe "create_issue" do
    it "raises a templated issue keyed to the workflow and subject" do
      result = execute("create_issue", { "title" => "Check {{description}}", "severity" => "error" })

      expect(result[:status]).to eq(:applied)
      issue = Issue.find(result[:issue_id])
      expect(issue.title).to eq("Check STARBUCKS #12")
      expect(issue.severity).to eq(Severity::Error)
      expect(issue.key).to eq("workflow:#{workflow.id}:CashTransaction:#{txn.id}")
    end
  end

  describe "trigger_sync" do
    it "enqueues the allowlisted job" do
      expect {
        expect(execute("trigger_sync", { "target" => "plaid" })[:status]).to eq(:applied)
      }.to have_enqueued_job(PlaidSyncJob)
    end

    it "enqueues recurring detection scoped to the run's household" do
      expect {
        expect(execute("trigger_sync", { "target" => "recurring_detection" })[:status]).to eq(:applied)
      }.to have_enqueued_job(Recurring::DetectJob).with(household_id: run.household_id)
    end

    it "rejects unknown targets" do
      result = execute("trigger_sync", { "target" => "rm -rf" })
      expect(result[:status]).to eq(:error)
    end
  end

  describe "run_workflow" do
    it "dispatches the target workflow with chain ancestry" do
      target = create(:workflow, name: "Child")

      result = nil
      expect {
        result = execute("run_workflow", { "workflow_id" => target.id })
      }.to have_enqueued_job(Workflows::ExecuteRunJob)

      expect(result[:status]).to eq(:applied)
      child = WorkflowRun.find(result[:run_id])
      expect(child.workflow_id).to eq(target.id)
      expect(child.triggered_by_run_id).to eq(run.id)
      expect(child.subject_id).to eq(txn.id)
    end

    it "skips inactive targets and errors on other households' workflows" do
      inactive = create(:workflow, name: "Off", active: false)
      expect(execute("run_workflow", { "workflow_id" => inactive.id })[:status]).to eq(:skipped)

      other = create(:workflow, name: "Foreign", household: create(:household, name: "Other"))
      expect(execute("run_workflow", { "workflow_id" => other.id })[:status]).to eq(:error)
    end
  end

  describe "PARAM_KEYS" do
    it "lists the params of every action type (the workflows API stores only these)" do
      expect(described_class::PARAM_KEYS.keys).to match_array(described_class.action_types)
    end

    it "permits nothing for an unknown action type" do
      expect(described_class.param_keys("nonexistent")).to eq([])
    end
  end
end
