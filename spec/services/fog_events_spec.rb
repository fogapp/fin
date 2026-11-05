require "rails_helper"

RSpec.describe FogEvents do
  let(:fog_env) { { "FOG_API_URL" => "http://fog.test", "FOG_API_TOKEN" => "apptok" } }
  let(:workflow) { create(:workflow, name: "Budget alerts") }
  let(:run) { create(:workflow_run, workflow: workflow, event_type: "budget.category_exceeded") }
  let(:notification) do
    Notification.create!(household: Current.household, title: "Dining over budget", body: "112% of budget",
                         severity: Severity::Warning, href: "/cashflow#section=budget", workflow_run: run)
  end

  describe ".notification" do
    it "publishes what the bell menu shows, linked against the configured origin" do
      stub_const("ENV", ENV.to_h.merge(fog_env, "FIN_WEBAUTHN_ORIGINS" => "https://fin.example.test"))
      posted = nil
      stub_request(:post, "http://fog.test/app/v1/events")
        .with(headers: { "Authorization" => "Bearer apptok" })
        .to_return { |request| (posted = JSON.parse(request.body)) && { status: 202, body: "{}" } }

      expect(described_class.notification(notification)).to eq(FogEvents::Outcome::Published)

      expect(posted).to include("specversion" => "1.0", "type" => "fin.notification",
                                "id" => "notification-#{notification.id}", "subject" => "Budget alerts")
      expect(posted["data"]).to eq(
        "title" => "Dining over budget", "body" => "112% of budget", "severity" => "warning",
        "link" => "https://fin.example.test/cashflow#section=budget",
        "workflow" => "Budget alerts", "event_type" => "budget.category_exceeded"
      )
    end

    it "sends nothing off fog" do
      stub_const("ENV", ENV.to_h.except("FOG_API_URL", "FOG_API_TOKEN"))

      expect(described_class.notification(notification)).to eq(FogEvents::Outcome::Unavailable)
      expect(a_request(:any, /./)).not_to have_been_made
    end

    it "records a failed publish on the activity timeline instead of raising" do
      stub_const("ENV", ENV.to_h.merge(fog_env))
      stub_request(:post, "http://fog.test/app/v1/events").to_return(status: 503)

      expect(described_class.notification(notification)).to eq(FogEvents::Outcome::Failed)
      entry = ActivityEntry.find_by!(source: "fog", event: "event.failed")
      expect(entry.severity).to eq(Severity::Warning)
      expect(entry.summary).to include("fin.notification", "503")
    end
  end

  describe "Notification's hook" do
    it "queues a publish for every notification on fog" do
      stub_const("ENV", ENV.to_h.merge(fog_env))
      expect { notification }.to have_enqueued_job(PublishNotificationEventJob)
    end

    it "queues nothing off fog" do
      stub_const("ENV", ENV.to_h.except("FOG_API_URL", "FOG_API_TOKEN"))
      expect { notification }.not_to have_enqueued_job(PublishNotificationEventJob)
    end

    it "publishes from the job" do
      stub_const("ENV", ENV.to_h.merge(fog_env))
      stub = stub_request(:post, "http://fog.test/app/v1/events")
        .with(body: hash_including("id" => "notification-#{notification.id}")).to_return(status: 202)

      PublishNotificationEventJob.perform_now(notification.id)

      expect(stub).to have_been_requested
    end
  end

  describe ".type_for" do
    it "folds a name into fog's type alphabet" do
      expect(described_class.type_for("budget.category_exceeded")).to eq("fin.budget.category_exceeded")
      expect(described_class.type_for("Weekly Digest!")).to eq("fin.weekly-digest")
      expect(described_class.type_for("!!!")).to eq("fin.event")
      expect(described_class.type_for("x" * 300)).to match(FogEvents::TYPE_PATTERN)
    end
  end

  describe ".event_id" do
    it "hashes ids that would exceed fog's bound, stably" do
      expect(described_class.event_id("run", "abc")).to eq("run-abc")
      long = described_class.event_id("x" * 200)
      expect(long.length).to be <= 128
      expect(described_class.event_id("x" * 200)).to eq(long)
    end
  end

  describe ".link" do
    it "is nil when Fin doesn't know its own address" do
      stub_const("ENV", ENV.to_h.except("FIN_WEBAUTHN_ORIGINS", "FIN_WEBAUTHN_RP_ID"))
      expect(described_class.link("/review")).to be_nil
    end

    it "falls back to the RP ID" do
      stub_const("ENV", ENV.to_h.except("FIN_WEBAUTHN_ORIGINS").merge("FIN_WEBAUTHN_RP_ID" => "fin.example.test"))
      expect(described_class.link("/review")).to eq("https://fin.example.test/review")
    end
  end
end
