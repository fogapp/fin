require "swagger_helper"

RSpec.describe "Activity, Notifications & System Health", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  let(:trace_id) { SecureRandom.uuid }

  def activity!(**attrs)
    ActivityEntry.create!({ occurred_at: Time.current, source: "plaid_sync", event: "sync.completed",
                            severity: "info", summary: "Synced 3 accounts", payload: { "accounts" => 3 },
                            duration_ms: 812 }.merge(attrs))
  end

  def notification!(**attrs)
    Notification.create!({ title: "Large charge", body: "$1,200 at Costco", severity: "warning",
                           href: "/transactions" }.merge(attrs))
  end

  # ── Activity ──────────────────────────────────────────────────────────────────

  path "/api/v1/activity" do
    get "The activity log (paged), or episodes grouped by trace" do
      tags "Activity"
      produces "application/json"
      parameter name: :source, in: :query, type: :string, required: false, description: "Comma-separated sources"
      parameter name: :severity, in: :query, required: false, schema: { "$ref" => "#/components/schemas/ActivitySeverity" }
      parameter name: :subject_type, in: :query, type: :string, required: false
      parameter name: :subject_id, in: :query, type: :string, format: :uuid, required: false
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :grouped, in: :query, type: :string, required: false,
                description: "Any value switches the response to ActivityGroupsResponse"

      entries_or_groups = {
        oneOf: [
          { "$ref" => "#/components/schemas/ActivityResponse" },
          { "$ref" => "#/components/schemas/ActivityGroupsResponse" }
        ]
      }

      response "200", "entries (ActivityResponse), or grouped episodes (ActivityGroupsResponse)" do
        schema entries_or_groups
        before do
          activity!(trace_id: trace_id, subject_type: "Account", subject_id: create(:account).id)
          activity!(source: "import", event: "import.failed", severity: "error", summary: "Bad CSV", duration_ms: nil)
        end
        run_test! do |response|
          expect(response.parsed_body["entries"].size).to eq(2)
        end
      end

      response "200", "entries (ActivityResponse), or grouped episodes (ActivityGroupsResponse)" do
        schema entries_or_groups
        let(:grouped) { "1" }
        before do
          activity!(trace_id: trace_id)
          activity!(trace_id: trace_id, source: "transfer_detection", event: "transfers.detected", severity: "warning")
          activity!(source: "system_audit", event: "audit.completed")
        end
        run_test! do |response|
          expect(response.parsed_body["groups"].size).to eq(2)
        end
      end
    end
  end

  path "/api/v1/activity/trace/{trace_id}" do
    parameter name: :trace_id, in: :path, type: :string, format: :uuid, required: true

    get "Everything stamped with one trace: entries, workflow runs, notifications" do
      tags "Activity"
      produces "application/json"

      response "200", "trace returned" do
        schema "$ref" => "#/components/schemas/ActivityTraceResponse"
        before do
          activity!(trace_id: trace_id)
          create(:workflow_run, trace_id: trace_id, status: "completed")
          notification!(trace_id: trace_id)
        end
        run_test!
      end
    end
  end

  # ── Notifications ─────────────────────────────────────────────────────────────

  path "/api/v1/notifications" do
    get "Recent notifications and the unread count" do
      tags "Notifications"
      produces "application/json"
      parameter name: :unread, in: :query, type: :string, enum: %w[true], required: false

      response "200", "notifications listed" do
        schema "$ref" => "#/components/schemas/NotificationsResponse"
        before do
          notification!
          notification!(title: "Sync failed", body: nil, severity: "error", href: nil, read_at: 1.hour.ago)
        end
        run_test! do |response|
          expect(response.parsed_body["unread_count"]).to eq(1)
        end
      end
    end
  end

  path "/api/v1/notifications/{id}/read" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Mark a notification read" do
      tags "Notifications"
      produces "application/json"

      response "200", "notification marked read" do
        schema "$ref" => "#/components/schemas/AppNotification"
        let(:id) { notification!.id }
        run_test!
      end
    end
  end

  path "/api/v1/notifications/read_all" do
    post "Mark every notification read" do
      tags "Notifications"

      response "204", "all marked read" do
        before { notification! }
        run_test!
      end
    end
  end

  # ── System health ─────────────────────────────────────────────────────────────

  path "/api/v1/system_health" do
    get "Latest run per background source, workflow and market-data health" do
      tags "System Health"
      produces "application/json"

      response "200", "health returned" do
        schema "$ref" => "#/components/schemas/SystemHealth"
        before do
          activity!
          activity!(source: "market_prices", event: "sync.failed", severity: "error", summary: "Tiingo 500")
          create(:workflow_run, status: "failed")
          InstrumentDataLink.create!(security: create(:security), provider: "tiingo", capability: "candles",
                                     consecutive_failures: 2, last_error: "Tiingo HTTP 500", last_attempt_at: 1.hour.ago)
        end
        run_test!
      end
    end
  end
end
