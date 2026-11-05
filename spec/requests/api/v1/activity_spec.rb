require "rails_helper"

RSpec.describe "Api::V1::Activity", type: :request do
  include ActiveJob::TestHelper

  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/activity" do
    it "lists entries newest-first with source and severity filters" do
      Activity.record(source: "plaid_sync", event: "sync.completed", summary: "Plaid: 3 added")
      Activity.record(source: "import", event: "import.completed", summary: "CSV done")
      Activity.record(source: "plaid_sync", event: "sync.failed", severity: Severity::Error, summary: "Plaid down")

      get "/api/v1/activity", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["meta"]).to include("total" => 3)

      get "/api/v1/activity", params: { source: "plaid_sync" }, headers: auth_headers
      expect(response.parsed_body["entries"].map { |e| e["source"] }.uniq).to eq([ "plaid_sync" ])

      get "/api/v1/activity", params: { severity: "error" }, headers: auth_headers
      expect(response.parsed_body["entries"].sole["summary"]).to eq("Plaid down")
    end

    it "filters by subject for per-record timelines" do
      txn = create(:cash_transaction, :bank, account: create(:account))
      Activity.record(source: "workflow", event: "run.completed", summary: "ran", subject: txn)
      Activity.record(source: "workflow", event: "run.completed", summary: "other")

      get "/api/v1/activity",
          params: { subject_type: "CashTransaction", subject_id: txn.id },
          headers: auth_headers
      expect(response.parsed_body["entries"].sole["summary"]).to eq("ran")
    end

    it "hides other households' entries" do
      other = create(:household, name: "Other")
      Activity.record(source: "import", event: "import.completed", summary: "theirs",
                      household_id: other.id)

      get "/api/v1/activity", headers: auth_headers
      expect(response.parsed_body["entries"]).to be_empty
    end
  end

  describe "GET /api/v1/activity/trace/:trace_id" do
    it "assembles entries, workflow runs, and notifications for one trace" do
      trace = SecureRandom.uuid
      Current.trace_id = trace
      workflow = create(:workflow)
      run = create(:workflow_run, workflow: workflow)
      Notification.create!(household: Current.household, title: "Heads up")
      Activity.record(source: "plaid_sync", event: "sync.completed", summary: "Plaid: 1 added")

      get "/api/v1/activity/trace/#{trace}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["entries"].sole["summary"]).to eq("Plaid: 1 added")
      expect(body["workflow_runs"].sole["id"]).to eq(run.id)
      expect(body["notifications"].sole["title"]).to eq("Heads up")
    end

    it "preloads run steps instead of loading them per run" do
      trace = SecureRandom.uuid
      Current.trace_id = trace
      workflow = create(:workflow)
      create_list(:workflow_run, 3, workflow: workflow)

      queries = count_queries { get "/api/v1/activity/trace/#{trace}", headers: auth_headers }

      expect(response.parsed_body["workflow_runs"].size).to eq(3)
      expect(queries.grep(/FROM "workflow_run_steps"/).size).to eq(1)
    end
  end

  describe "trace propagation through the job graph" do
    it "stamps one trace across dispatch, run, executor entry, and notification" do
      workflow = create(:workflow, name: "Notify on create", trigger_type: "cash_transaction.created")
      workflow.replace_steps!([
        { kind: "action", config: { action_type: "notify", params: { title: "New txn {{description}}" } } }
      ])
      Workflows::Events.reset_cache

      txn = nil
      perform_enqueued_jobs do
        txn = create(:cash_transaction, :bank, account: create(:account), description: "TRACE ME")
      end

      run = WorkflowRun.where(subject_id: txn.id).sole
      expect(run.trace_id).to be_present

      entry = ActivityEntry.where(source: "workflow").sole
      expect(entry.trace_id).to eq(run.trace_id)
      expect(entry.event).to eq("run.completed")

      notification = Notification.where(title: "New txn TRACE ME").sole
      expect(notification.trace_id).to eq(run.trace_id)
    end
  end

  describe "GET /api/v1/system_health" do
    it "reports last activity per source, workflow stats, and provider errors" do
      Activity.record(source: "plaid_sync", event: "sync.completed", summary: "old", duration_ms: 5)
      Activity.record(source: "plaid_sync", event: "sync.failed", severity: Severity::Error, summary: "newest")
      create(:workflow_run, workflow: create(:workflow), status: "failed")
      sec = create(:security, ticker: "FAILY")
      InstrumentDataLink.create!(security: sec, capability: "candles", provider: "alpha_vantage",
                                 consecutive_failures: 2, last_error: "AlphaVantage: rate limited",
                                 last_attempt_at: Time.current)

      get "/api/v1/system_health", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      plaid = body["sources"].find { |s| s["source"] == "plaid_sync" }
      expect(plaid["summary"]).to eq("newest")
      expect(plaid["severity"]).to eq("error")
      expect(body).not_to have_key("queue") # infrastructure noise, removed
      expect(body["workflows"]).to include("runs_7d" => 1, "failed_7d" => 1)
      expect(body["errors_24h"]).to eq(1)
      av = body["market_data"]["providers"].find { |p| p["provider"] == "alpha_vantage" }
      expect(av["failing"]).to eq(1)
      expect(av["last_error"]).to match(/rate limited/)
    end

    it "computes staleness with batched price lookups instead of per-security queries" do
      3.times do |i|
        sec = create(:security, ticker: "HLD#{i}")
        create(:position_snapshot, security: sec, quantity: 1, market_value: 100)
      end
      fresh = create(:security, ticker: "FRESH")
      create(:position_snapshot, security: fresh, quantity: 1, market_value: 100)
      create(:market_price, security: fresh, date: Date.current, close: 10.0)

      price_queries = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        # Column-definition loads (name "SCHEMA") fire on first model touch
        # and mention the table name too — they aren't data queries.
        next if payload[:name] == "SCHEMA"
        sql = payload[:sql].to_s
        next unless sql.start_with?("SELECT")
        price_queries << sql if [ '"instrument_quotes"', '"candles"', '"market_prices"' ].any? { |t| sql.include?(t) }
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/api/v1/system_health", headers: auth_headers
      end

      expect(response).to have_http_status(:ok)
      # The three securities without any price are stale; FRESH has a
      # same-day close.
      expect(response.parsed_body["market_data"]["stale_held_instruments"]).to eq(3)
      # One batched query per price store (quotes, candles, legacy prices) —
      # not 1-3 queries per held security.
      expect(price_queries.length).to eq(3)
    end
  end

  describe "retention" do
    it "prunes old routine entries and finished runs, keeps errors and failures" do
      old_info  = Activity.record(source: "import", event: "import.completed", summary: "old info")
      old_error = Activity.record(source: "import", event: "import.failed", severity: Severity::Error, summary: "old err")
      ActivityEntry.where(id: [ old_info.id, old_error.id ]).update_all(occurred_at: 100.days.ago)
      fresh = Activity.record(source: "import", event: "import.completed", summary: "fresh")

      workflow = create(:workflow)
      old_done   = create(:workflow_run, workflow: workflow, status: "completed", created_at: 100.days.ago)
      old_failed = create(:workflow_run, workflow: workflow, status: "failed", created_at: 100.days.ago)

      PruneActivityJob.perform_now

      expect(ActivityEntry.pluck(:id)).to contain_exactly(old_error.id, fresh.id)
      expect(WorkflowRun.pluck(:id)).to contain_exactly(old_failed.id)
    end
  end

  describe "GET /activity?grouped=true" do
    it "collapses same-trace entries into one group led by the worst severity" do
      trace = SecureRandom.uuid
      travel_to Time.current do
        Current.set(trace_id: trace) do
          Activity.record(source: "plaid", event: "sync.started", summary: "Sync started", household_id: Current.household.id)
          Activity.record(source: "workflow", event: "run.failed", severity: Severity::Error,
                          summary: "Run blew up", household_id: Current.household.id)
        end
        Current.set(trace_id: SecureRandom.uuid) do
          Activity.record(source: "import", event: "import.completed", summary: "CSV imported", household_id: Current.household.id)
        end
      end

      get "/api/v1/activity", params: { grouped: true }, headers: auth_headers

      body = response.parsed_body
      expect(body["groups"].size).to eq(2)

      episode = body["groups"].find { |g| g["count"] == 2 }
      expect(episode["trace_id"]).to eq(trace)
      expect(episode["severities"]).to eq({ "info" => 1, "error" => 1 })
      expect(episode["sources"]).to eq(%w[plaid workflow])
      expect(episode["lead"]["summary"]).to eq("Run blew up")

      single = body["groups"].find { |g| g["count"] == 1 }
      expect(single["lead"]["summary"]).to eq("CSV imported")
    end

    it "treats entries without a trace as singleton groups" do
      2.times do |i|
        ActivityEntry.create!(household_id: Current.household.id, source: "system", event: "e#{i}",
                              severity: "info", summary: "no trace #{i}", occurred_at: Time.current)
      end

      get "/api/v1/activity", params: { grouped: true }, headers: auth_headers

      expect(response.parsed_body["groups"].size).to eq(2)
      expect(response.parsed_body["groups"].map { |g| g["count"] }).to eq([ 1, 1 ])
    end
  end
end
