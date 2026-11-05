require "rails_helper"

RSpec.describe "Api::V1::Workflows", type: :request do
  let(:token)        { create(:api_token) }
  let(:auth_headers) { { "Authorization" => "Bearer #{token.raw_token}" } }

  describe "GET /api/v1/workflows" do
    it "returns 401 without a token" do
      get "/api/v1/workflows"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists workflows with run summaries" do
      workflow = create(:workflow, name: "Categorize coffee")
      create(:workflow_run, workflow: workflow, status: "completed")

      get "/api/v1/workflows", headers: auth_headers

      expect(response).to have_http_status(:ok)
      entry = response.parsed_body.sole
      expect(entry).to include("name" => "Categorize coffee", "run_count" => 1,
                               "last_run_status" => "completed")
    end
  end

  describe "POST /api/v1/workflows" do
    it "creates a workflow with a nested step tree" do
      merchant = create(:merchant)
      post "/api/v1/workflows", headers: auth_headers, as: :json, params: {
        name: "Rent watcher",
        trigger_type: "cash_transaction.created",
        steps: [
          { kind: "branch",
            config: { match_all: true,
                      conditions: [ { field: "amount", operator: "greater_than", value: "2000" } ] },
            children: [
              { kind: "action", config: { action_type: "assign_merchant", params: { merchant_id: merchant.id } } },
              { kind: "wait", config: { duration_seconds: 3600 },
                children: [ { kind: "action", config: { action_type: "set_memo", params: { value: "checked" } } } ] }
            ] }
        ]
      }

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["steps"].length).to eq(1)
      branch = body["steps"].first
      expect(branch["kind"]).to eq("branch")
      expect(branch["children"].map { |c| c["kind"] }).to eq(%w[action wait])
      expect(branch["children"].last["children"].sole["kind"]).to eq("action")
    end

    it "rejects unknown trigger types" do
      post "/api/v1/workflows", headers: auth_headers, as: :json,
           params: { name: "Bad", trigger_type: "weather.changed" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "stores the keys each trigger and step reads, and drops everything else" do
      tag = create(:tag)
      post "/api/v1/workflows", headers: auth_headers, as: :json, params: {
        name: "Allowlisted", trigger_type: "cash_transaction.updated",
        trigger_config: { changed_fields: [ "amount" ], injected: "x" },
        steps: [
          { kind: "branch", injected: "x",
            config: { match_all: false, injected: "x",
                      conditions: [ { field: "amount", operator: "in", value: "1,2", injected: "x" } ] },
            children: [
              { kind: "action",
                config: { action_type: "add_tag", stop_on_error: true, injected: "x",
                          params: { tag_id: [ tag.id ], merchant_id: "not-an-add_tag-key" } } },
              { kind: "action",
                config: { action_type: "notify",
                          params: { title: "T", body: "B", severity: "warning", href: "/x", url: "https://evil" } } }
            ] },
          { kind: "branch", config: { else: true } },
          { kind: "wait", config: { duration_seconds: 60, injected: "x" } }
        ]
      }

      expect(response).to have_http_status(:created)
      workflow = Workflow.find(response.parsed_body["id"])
      expect(workflow.trigger_config).to eq("changed_fields" => [ "amount" ])

      branch, else_branch, wait = workflow.steps_tree
      expect(branch[:config]).to eq("match_all" => false,
                                    "conditions" => [ { "field" => "amount", "operator" => "in", "value" => "1,2" } ])
      tag_step, notify_step = branch[:children]
      expect(tag_step[:config]).to eq("action_type" => "add_tag", "stop_on_error" => true,
                                      "params" => { "tag_id" => [ tag.id ] })
      expect(notify_step[:config]["params"]).to eq("title" => "T", "body" => "B", "severity" => "warning", "href" => "/x")
      expect(else_branch[:config]).to eq("else" => true)
      expect(wait[:config]).to eq("duration_seconds" => 60)
    end

    it "keeps monitor and schedule trigger configs whole" do
      post "/api/v1/workflows", headers: auth_headers, as: :json, params: {
        name: "Low balance", trigger_type: "monitor",
        trigger_config: { subject: "account", match_all: true,
                          conditions: [ { field: "balance_usd", operator: "less_than", value: "500" } ] }
      }
      expect(response).to have_http_status(:created)
      expect(Workflow.find(response.parsed_body["id"]).trigger_config).to eq(
        "subject" => "account", "match_all" => true,
        "conditions" => [ { "field" => "balance_usd", "operator" => "less_than", "value" => "500" } ]
      )

      post "/api/v1/workflows", headers: auth_headers, as: :json, params: {
        name: "Weekly", trigger_type: "schedule",
        trigger_config: { frequency: "weekly", at: "05:30", day_of_week: 2 }
      }
      expect(response).to have_http_status(:created)
      expect(Workflow.find(response.parsed_body["id"]).trigger_config)
        .to eq("frequency" => "weekly", "at" => "05:30", "day_of_week" => 2)
    end

    it "rejects malformed steps" do
      post "/api/v1/workflows", headers: auth_headers, as: :json, params: {
        name: "Bad steps", trigger_type: "cash_transaction.created",
        steps: [ { kind: "action", config: {} } ]
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/workflows/:id" do
    it "replaces the step tree" do
      workflow = create(:workflow)
      workflow.replace_steps!([ { kind: "action", config: { action_type: "set_memo", params: { value: "old" } } } ])

      patch "/api/v1/workflows/#{workflow.id}", headers: auth_headers, as: :json, params: {
        steps: [ { kind: "action", config: { action_type: "set_memo", params: { value: "new" } } } ]
      }

      expect(response).to have_http_status(:ok)
      expect(workflow.reload.steps.sole.config.dig("params", "value")).to eq("new")
    end

    it "is hidden from other households" do
      other_household = create(:household, name: "B")
      other_user      = create(:user, email: "b@example.com")
      create(:household_membership, user: other_user, household: other_household)
      other_token = create(:api_token, user: other_user, household: other_household)
      workflow = create(:workflow)

      patch "/api/v1/workflows/#{workflow.id}",
            headers: { "Authorization" => "Bearer #{other_token.raw_token}" },
            as: :json, params: { name: "hijack" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/workflows/catalog" do
    it "returns trigger types with fields and available actions" do
      get "/api/v1/workflows/catalog", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      types = body["triggers"].map { |t| t["type"] }
      expect(types).to include("cash_transaction.created", "account.updated", "plaid.sync_completed",
                               "equity.exercise_window_closing",
                               "tax.quarterly_due_approaching", "tax.safe_harbor_behind",
                               "tax.contribution_limit_approaching", "tax.document_overdue",
                               "tax.wash_sale_detected")
      cash_created = body["triggers"].find { |t| t["type"] == "cash_transaction.created" }
      expect(cash_created["fields"]).to have_key("description")
      # Operators are Conditions::Operator instances internally; the wire
      # format must stay plain strings.
      expect(cash_created["fields"]["description"]["operators"])
        .to eq(%w[matches equals not_equals contains blank present])
      account_updated = body["triggers"].find { |t| t["type"] == "account.updated" }
      expect(account_updated["fields"]["balance_usd"]["operators"])
        .to eq(%w[equals greater_than less_than])
      expect(body["actions"]).to include("assign_merchant", "set_memo", "transfer_to_account")
    end
  end

  describe "GET /api/v1/workflow_runs" do
    it "paginates runs with step detail on show" do
      workflow = create(:workflow)
      workflow.replace_steps!([ { kind: "action", config: { action_type: "set_memo", params: { value: "x" } } } ])
      txn = create(:cash_transaction, :bank, account: create(:account))
      run = create(:workflow_run, workflow: workflow,
                   subject_type: "CashTransaction", subject_id: txn.id)
      Workflows::Executor.new(run).call

      get "/api/v1/workflow_runs", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["runs"].length).to eq(1)
      expect(response.parsed_body["meta"]).to include("total" => 1)

      get "/api/v1/workflow_runs/#{run.id}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["steps"].sole).to include("status" => "applied", "step_kind" => "action")
    end

    it "loads run_steps in one query for the whole page (revertible is derived from them)" do
      workflow = create(:workflow)
      workflow.replace_steps!([ { kind: "action", config: { action_type: "set_memo", params: { value: "x" } } } ])
      account = create(:account)
      3.times do
        txn = create(:cash_transaction, :bank, account: account)
        run = create(:workflow_run, workflow: workflow,
                     subject_type: "CashTransaction", subject_id: txn.id)
        Workflows::Executor.new(run).call
      end

      step_queries = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql].to_s
        step_queries << sql if sql.start_with?("SELECT") && sql.include?('"workflow_run_steps"')
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/api/v1/workflow_runs", headers: auth_headers
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["runs"].length).to eq(3)
      expect(response.parsed_body["runs"]).to all(include("revertible" => true))
      expect(step_queries.length).to eq(1)
    end
  end

  describe "DELETE /workflows/:id" do
    it "refuses to delete a system (seeded) workflow" do
      workflow = create(:workflow, trigger_type: "schedule",
                        trigger_config: { "frequency" => "daily", "at" => "05:00" },
                        seed_key: "market_data_sync")

      delete "/api/v1/workflows/#{workflow.id}", headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(workflow.reload).to be_persisted
    end

    it "deletes user workflows" do
      workflow = create(:workflow, trigger_type: "cash_transaction.created")

      delete "/api/v1/workflows/#{workflow.id}", headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(Workflow.exists?(workflow.id)).to be(false)
    end
  end

  describe "revert endpoints" do
    let(:comcast) { create(:merchant, name: "Comcast") }

    def executed_run(workflow, txn)
      run = workflow.runs.create!(
        household_id: workflow.household_id, subject_type: "CashTransaction",
        subject_id: txn.id, event_type: "manual.test", event_payload: {}, status: "pending"
      )
      Workflows::Executor.new(run).call
      run.reload
    end

    it "POST /workflow_runs/:id/revert undoes the run and reports counts" do
      workflow = create(:workflow, trigger_type: "cash_transaction.created")
      workflow.replace_steps!([ { kind: "action", config: { "action_type" => "assign_merchant", "params" => { "merchant_id" => comcast.id } } } ])
      txn = create(:cash_transaction, :credit_card, :sale)
      run = executed_run(workflow, txn)
      expect(txn.reload.merchant_id).to eq(comcast.id)

      post "/api/v1/workflow_runs/#{run.id}/revert", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("reverted" => 1)
      expect(txn.reload.merchant_id).to be_nil
      expect(run.reload.reverted_at).to be_present
    end

    it "POST /workflows/:id/revert_runs queues the bulk revert" do
      workflow = create(:workflow, trigger_type: "cash_transaction.created")

      expect {
        post "/api/v1/workflows/#{workflow.id}/revert_runs", headers: auth_headers
      }.to have_enqueued_job(Workflows::RevertRunsJob).with(workflow.id, nil)
      expect(response.parsed_body["status"]).to eq("queued")
    end

    it "serializes revertibility on runs" do
      workflow = create(:workflow, trigger_type: "cash_transaction.created")
      workflow.replace_steps!([ { kind: "action", config: { "action_type" => "assign_merchant", "params" => { "merchant_id" => comcast.id } } } ])
      txn = create(:cash_transaction, :credit_card, :sale)
      run = executed_run(workflow, txn)

      get "/api/v1/workflow_runs/#{run.id}", headers: auth_headers
      expect(response.parsed_body).to include("revertible" => true, "reverted_at" => nil)

      post "/api/v1/workflow_runs/#{run.id}/revert", headers: auth_headers
      get "/api/v1/workflow_runs/#{run.id}", headers: auth_headers
      expect(response.parsed_body["revertible"]).to be(false)
      expect(response.parsed_body["reverted_at"]).to be_present
    end
  end

  describe "POST /workflows/:id/run_now" do
    it "queues an apply-to-existing pass for event workflows" do
      workflow = create(:workflow, trigger_type: "cash_transaction.created")

      expect {
        post "/api/v1/workflows/#{workflow.id}/run_now", headers: auth_headers
      }.to have_enqueued_job(Workflows::ApplyToExistingJob).with(workflow.id)
      expect(response.parsed_body).to include("status" => "queued", "mode" => "apply_to_existing")
    end

    it "queues a monitor evaluation for monitor workflows" do
      workflow = create(:workflow, trigger_type: "monitor",
                        trigger_config: { "subject" => "account",
                                          "conditions" => [ { "field" => "balance", "operator" => "less_than", "value" => "0" } ] })

      expect {
        post "/api/v1/workflows/#{workflow.id}/run_now", headers: auth_headers
      }.to have_enqueued_job(Workflows::EvaluateMonitorJob).with(workflow.id)
      expect(response.parsed_body["mode"]).to eq("monitor")
    end

    it "fires a scheduled workflow once now without moving its schedule" do
      workflow = create(:workflow, trigger_type: "schedule",
                        trigger_config: { "frequency" => "hourly", "every_hours" => 6 })
      next_at = workflow.reload.next_scheduled_at

      expect {
        post "/api/v1/workflows/#{workflow.id}/run_now", headers: auth_headers
      }.to change { workflow.runs.count }.by(1)
        .and have_enqueued_job(Workflows::ExecuteRunJob)
      expect(Workflows::ApplyToExistingJob).not_to have_been_enqueued

      run = workflow.runs.last
      expect(run).to have_attributes(event_type: "schedule.manual", subject_type: nil, status: WorkflowRun::Status::Pending)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include("status" => "queued", "mode" => "schedule", "run_id" => run.id)
      expect(workflow.reload.next_scheduled_at).to eq(next_at)
    end
  end

  describe "GET /workflow_runs?grouped=true" do
    let(:workflow) { create(:workflow, trigger_type: "cash_transaction.created") }
    # trace_id is a uuid column — arbitrary strings cast to nil silently.
    let(:trace_batch) { SecureRandom.uuid }
    let(:trace_solo)  { SecureRandom.uuid }

    def make_run(txn, trace:, status: "completed")
      workflow.runs.create!(
        household_id: workflow.household_id, subject_type: "CashTransaction",
        subject_id: txn.id, event_type: "manual.apply_to_existing",
        event_payload: {}, status: status, trace_id: trace
      )
    end

    it "collapses runs sharing a trace into one group with status tallies" do
      txns = 4.times.map { create(:cash_transaction, :credit_card, :sale) }
      txns.first(3).each { |t| make_run(t, trace: trace_batch) }
      make_run(txns[0], trace: trace_batch, status: "failed")
      make_run(txns.last, trace: trace_solo)

      get "/api/v1/workflow_runs", params: { workflow_id: workflow.id, grouped: true },
                                   headers: auth_headers

      body = response.parsed_body
      expect(body["groups"].size).to eq(2)

      batch = body["groups"].find { |g| g["trace_id"] == trace_batch }
      expect(batch["count"]).to eq(4)
      expect(batch["statuses"]).to eq({ "completed" => 3, "failed" => 1 })
      expect(batch["run"]).to be_nil

      solo = body["groups"].find { |g| g["trace_id"] == trace_solo }
      expect(solo["count"]).to eq(1)
      expect(solo["run"]).to include("id", "status")
    end

    it "keeps a status filter inside each group" do
      txns = 2.times.map { create(:cash_transaction, :credit_card, :sale) }
      # Created first so it would be `.first` if the single-run lookup
      # ignored the filter.
      completed = make_run(txns[0], trace: trace_batch)
      failed    = make_run(txns[1], trace: trace_batch, status: "failed")

      get "/api/v1/workflow_runs", params: { workflow_id: workflow.id, grouped: true, status: "failed" },
                                   headers: auth_headers

      group = response.parsed_body["groups"].sole
      expect(group["count"]).to eq(1)
      expect(group["statuses"]).to eq({ "failed" => 1 })
      expect(group["run"]["id"]).to eq(failed.id)
      expect(group["run"]["id"]).not_to eq(completed.id)
    end

    it "filters runs by trace_id for group expansion" do
      trace_a = SecureRandom.uuid
      txn = create(:cash_transaction, :credit_card, :sale)
      make_run(txn, trace: trace_a)
      make_run(txn, trace: SecureRandom.uuid)

      get "/api/v1/workflow_runs", params: { workflow_id: workflow.id, trace_id: trace_a },
                                   headers: auth_headers

      runs = response.parsed_body["runs"]
      expect(runs.size).to eq(1)
    end

    it "keeps same-trace runs of different workflows in separate groups" do
      shared = SecureRandom.uuid
      other = create(:workflow, trigger_type: "cash_transaction.created", name: "Other")
      txn = create(:cash_transaction, :credit_card, :sale)
      make_run(txn, trace: shared)
      other.runs.create!(
        household_id: other.household_id, subject_type: "CashTransaction",
        subject_id: txn.id, event_type: "cash_transaction.created",
        event_payload: {}, status: "completed", trace_id: shared
      )

      get "/api/v1/workflow_runs", params: { grouped: true }, headers: auth_headers

      shared_groups = response.parsed_body["groups"].select { |g| g["trace_id"] == shared }
      expect(shared_groups.size).to eq(2)
      expect(shared_groups.map { |g| g["count"] }).to eq([ 1, 1 ])
    end
  end

  describe "POST /api/v1/workflows/:id/apply_to_existing" do
    it "returns 401 without authentication" do
      workflow = create(:workflow)
      post "/api/v1/workflows/#{workflow.id}/apply_to_existing"
      expect(response).to have_http_status(:unauthorized)
    end

    it "queues the backfill job and echoes the workflow id" do
      workflow = create(:workflow)

      expect {
        post "/api/v1/workflows/#{workflow.id}/apply_to_existing", headers: auth_headers
      }.to have_enqueued_job(Workflows::ApplyToExistingJob).with(workflow.id)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq("status" => "queued", "workflow_id" => workflow.id)
    end

    it "returns 404 for an unknown workflow without queueing anything" do
      expect {
        post "/api/v1/workflows/#{SecureRandom.uuid}/apply_to_existing", headers: auth_headers
      }.not_to have_enqueued_job(Workflows::ApplyToExistingJob)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a workflow in another household" do
      other = Current.set(household: create(:household)) { create(:workflow) }

      expect {
        post "/api/v1/workflows/#{other.id}/apply_to_existing", headers: auth_headers
      }.not_to have_enqueued_job(Workflows::ApplyToExistingJob)

      expect(response).to have_http_status(:not_found)
    end
  end
end
