require "swagger_helper"

RSpec.describe "Workflows", type: :request do
  let(:token)         { create(:api_token) }
  let(:Authorization) { "Bearer #{token.raw_token}" }

  STEP_INPUT = {
    type: :object,
    properties: {
      kind:     { "$ref" => "#/components/schemas/WorkflowStepKind" },
      config:   { type: :object, additionalProperties: true },
      children: { type: :array, items: { type: :object, additionalProperties: true } }
    },
    required: %w[kind config]
  }.freeze

  WORKFLOW_INPUT = {
    type: :object,
    properties: {
      name:           { type: :string },
      description:    { type: :string, nullable: true },
      trigger_type:   { type: :string },
      trigger_config: { type: :object, additionalProperties: true },
      active:         { type: :boolean },
      position:       { type: :integer },
      steps:          { type: :array, items: STEP_INPUT, description: "Replaces the whole step tree when present" }
    }
  }.freeze

  let(:workflow) do
    create(:workflow, name: "Tag coffee", description: "Coffee shops get a memo").tap do |w|
      branch = create(:workflow_step, :branch, workflow: w, position: 0)
      create(:workflow_step, workflow: w, parent: branch, position: 0)
    end
  end

  # A run with an applied, undoable step so `revertible` is exercised.
  let(:run) do
    txn = create(:cash_transaction)
    create(:workflow_run, workflow: workflow, status: "completed", subject_type: "CashTransaction", subject_id: txn.id,
                          event_payload: { "id" => txn.id }, started_at: 1.minute.ago, finished_at: Time.current,
                          trace_id: SecureRandom.uuid).tap do |r|
      WorkflowRunStep.create!(workflow_run: r, workflow_step: workflow.steps.find_by(kind: "action"), status: "applied",
                              output: { "undo" => { "memo" => nil } })
    end
  end

  # ── Workflows ─────────────────────────────────────────────────────────────────

  path "/api/v1/workflows" do
    get "List workflows with their latest run" do
      tags "Workflows"
      produces "application/json"

      response "200", "workflows listed" do
        schema type: :array, items: { "$ref" => "#/components/schemas/WorkflowSummary" }
        before do
          run
          create(:workflow, name: "Nightly sync", trigger_type: "schedule", trigger_config: { "frequency" => "daily", "at" => "05:00" })
        end
        run_test!
      end
    end

    post "Create a workflow" do
      tags "Workflows"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: WORKFLOW_INPUT

      response "201", "workflow created" do
        schema "$ref" => "#/components/schemas/WorkflowDetail"
        let(:body) do
          { name: "Memo big spends", trigger_type: "cash_transaction.created",
            steps: [ { kind: "action", config: { action_type: "set_memo", params: { value: "big" } }, children: [] } ] }
        end
        run_test!
      end

      response "422", "invalid workflow" do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:body) { { name: "", trigger_type: "cash_transaction.created" } }
        run_test!
      end
    end
  end

  path "/api/v1/workflows/catalog" do
    get "Trigger types with their condition fields, and action types" do
      tags "Workflows"
      produces "application/json"

      response "200", "catalog returned" do
        schema "$ref" => "#/components/schemas/WorkflowCatalog"
        run_test!
      end
    end
  end

  path "/api/v1/workflows/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "A workflow and its step tree" do
      tags "Workflows"
      produces "application/json"

      response "200", "workflow returned" do
        schema "$ref" => "#/components/schemas/WorkflowDetail"
        let(:id) { workflow.id }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end

    patch "Update a workflow (steps replace the tree)" do
      tags "Workflows"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: WORKFLOW_INPUT

      response "200", "workflow updated" do
        schema "$ref" => "#/components/schemas/WorkflowDetail"
        let(:id)   { workflow.id }
        let(:body) { { active: false } }
        run_test!
      end
    end

    delete "Delete a workflow (system workflows can only be deactivated)" do
      tags "Workflows"

      response "204", "workflow deleted" do
        let(:id) { workflow.id }
        run_test!
      end

      response "422", "system workflow" do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { create(:workflow, seed_key: "market_data_sync").id }
        run_test!
      end
    end
  end

  path "/api/v1/workflows/{id}/run_now" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Run a workflow now (monitors evaluate; others apply to existing records)" do
      tags "Workflows"
      produces "application/json"

      response "202", "run queued" do
        schema "$ref" => "#/components/schemas/Queued"
        let(:id) { workflow.id }
        run_test! do |response|
          expect(response.parsed_body["mode"]).to eq("apply_to_existing")
        end
      end
    end
  end

  path "/api/v1/workflows/{id}/apply_to_existing" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Apply a workflow to existing records" do
      tags "Workflows"
      produces "application/json"

      response "202", "apply queued" do
        schema "$ref" => "#/components/schemas/Queued"
        let(:id) { workflow.id }
        run_test!
      end
    end
  end

  path "/api/v1/workflows/{id}/revert_runs" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Revert a workflow's runs, optionally since a time" do
      tags "Workflows"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object, properties: { since: { type: :string, format: "date-time" } }
      }

      response "202", "revert queued" do
        schema "$ref" => "#/components/schemas/Queued"
        let(:id)   { workflow.id }
        let(:body) { { since: 1.day.ago.iso8601 } }
        run_test!
      end
    end
  end

  # ── Workflow runs ─────────────────────────────────────────────────────────────

  path "/api/v1/workflow_runs" do
    get "List workflow runs (paged), or runs grouped by trace" do
      tags "Workflow Runs"
      produces "application/json"
      parameter name: :workflow_id, in: :query, type: :string, format: :uuid, required: false
      parameter name: :status, in: :query, required: false, schema: { "$ref" => "#/components/schemas/WorkflowRunStatus" }
      parameter name: :trace_id, in: :query, type: :string, format: :uuid, required: false
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :grouped, in: :query, type: :string, required: false,
                description: "Any value switches the response to WorkflowRunGroupsResponse"

      # Both shapes share the 200; the example groups below exercise each.
      runs_or_groups = {
        oneOf: [
          { "$ref" => "#/components/schemas/WorkflowRunsResponse" },
          { "$ref" => "#/components/schemas/WorkflowRunGroupsResponse" }
        ]
      }

      response "200", "runs listed (WorkflowRunsResponse), or grouped (WorkflowRunGroupsResponse)" do
        schema runs_or_groups
        before { run }
        run_test! do |response|
          expect(response.parsed_body["runs"].first["revertible"]).to be(true)
        end
      end

      response "200", "runs listed (WorkflowRunsResponse), or grouped (WorkflowRunGroupsResponse)" do
        schema runs_or_groups
        let(:grouped) { "1" }
        before do
          run
          create(:workflow_run, workflow: workflow, status: "failed", trace_id: SecureRandom.uuid, error: "boom")
        end
        run_test! do |response|
          expect(response.parsed_body["groups"].size).to eq(2)
        end
      end
    end
  end

  path "/api/v1/workflow_runs/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    get "A run and its step results" do
      tags "Workflow Runs"
      produces "application/json"

      response "200", "run returned" do
        schema "$ref" => "#/components/schemas/WorkflowRunDetail"
        let(:id) { run.id }
        run_test!
      end
    end
  end

  path "/api/v1/workflow_runs/{id}/revert" do
    parameter name: :id, in: :path, type: :string, format: :uuid, required: true

    post "Undo what a run applied" do
      tags "Workflow Runs"
      produces "application/json"

      response "200", "run reverted" do
        schema "$ref" => "#/components/schemas/WorkflowRunRevertResult"
        let(:id) { run.id }
        run_test!
      end
    end
  end
end
