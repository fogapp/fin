# Fin Workflow Engine — Design

Status: implemented 2026-07-03 (phases A–F). This is the original design
record; the code has moved on in a few places:

- The old rules engine (`RulesEngine::*`, the `/rules` endpoints and tables)
  is gone. Conditions are evaluated by `Conditions::*` (registry, operators,
  SQL translation for match previews) and actions live natively in
  `Workflows::Actions` / `Workflows::ActionExecutor`, not as delegates.
- Schedule triggers were added after all (`Workflows::Schedule`,
  `Workflows::ScheduleTickJob`: hourly/daily/weekly/monthly), despite the
  "no cron triggers" goal below.
- Dry-run preview, apply-to-existing (`Workflows::ApplyToExistingJob`) and
  undo (`Workflows::Revert`, `RevertRunsJob`) were added on top of the
  engine described here.
- The `recurring_pattern` registry model became `recurring_series` (see
  `subscriptions-redesign.md`); `transfer_to_account` joined the data actions.

## Goals

Replace the flat condition→action rules engine with a general workflow engine:

- **Triggers**: record lifecycle events across a broad model registry, app-level
  domain events (sync completed, import finished, transfer candidate detected,
  recurring charge overdue), and threshold monitors (balance below X, spend
  over budget, price moved >N%). No user-facing cron triggers (deliberately
  out of scope; monitors cover the "watch for state" cases).
- **Shape**: branching graph per workflow — trigger → if/elsif/else branches →
  ordered action steps, with `wait` steps that park a run and resume later.
  Tree, not DAG: no parallel joins, no approval gates (future work).
- **Actions**: existing data mutations (assign merchant/category/account,
  tag, memo, loan link, mark-as-transfer), plus notifications (in-app +
  configurable webhook), outbound webhooks, record creation (issues),
  sync triggering, and invoking other workflows.
- **Delivery**: backend engine + a new builder UI replacing the /rules pages.
  Existing rules migrate as single-branch workflows.

## Architecture

### Events (Phase A)

`Workflows::Events.publish(type, subject:, payload: {})` is the single choke
point. It no-ops when the household has no active workflows for the type
(cheap guard query, cached) and otherwise enqueues `Workflows::DispatchJob`.

Sources:
1. **Record lifecycle** — `EmitsWorkflowEvents` concern (generalizes
   `TriggersRules`) included in registry models. Emits
   `<model_key>.created|updated|deleted` with `changes` (saved_changes keys)
   in the payload. Registry: cash_transaction, investment_transaction,
   account, transfer, loan, recurring_pattern, position_snapshot, merchant.
   Bulk paths (`update_all`, importers) emit batch events explicitly.
2. **App events** — emitted from services:
   `plaid.sync_completed`, `coinbase.sync_completed`, `import.completed`,
   `transfer.candidate_detected`, `recurring_charge.overdue`,
   `workflow.run_failed` (meta-event for alerting on broken automations).
3. **Monitors** (Phase D) — see below.

Events are ephemeral (job args), not persisted; runs are the durable audit
trail. `Current.household` is captured at publish time and travels with the
event.

### Data model (Phase B)

- `workflows`: household_id, name, description, trigger_type (string, from
  the catalog), trigger_config (jsonb: event filters, e.g. only `updated`
  events whose `changes` include `merchant_id`; monitor definitions in
  Phase D), active, position.
- `workflow_steps`: workflow_id, parent_id (nullable — root steps hang off
  the trigger), position (order among siblings), kind:
  - `branch` — config: `{match_all: bool, conditions: [{field, operator,
    value}], else: bool}`. Sibling branches at the same level evaluate in
    position order, first match wins (if/elsif/else). Children execute when
    the branch matches.
  - `action` — config: `{action_type, params}`.
  - `wait` — config: `{duration_seconds}`. Parks the run; children resume
    after the delay against the *reloaded* subject.
- `workflow_runs`: workflow_id, household_id, subject (polymorphic type/id),
  event_type, event_payload (jsonb), status (running/waiting/completed/
  failed/cancelled), cursor_step_id, triggered_by_run_id, error, timestamps.
- `workflow_run_steps`: run_id, step_id, status (matched/not_matched/
  applied/skipped/error/waiting), output (jsonb), timestamps, resume_at.

### Execution (Phase B)

`Workflows::ExecuteRunJob(run_id)` walks the tree depth-first:
- branch siblings: evaluate conditions with the existing
  `RulesEngine::ConditionEvaluator` (kept — it is parity-tested); first
  matching branch's children run, others recorded not_matched.
- action steps: `Workflows::Actions` registry. Data actions delegate to the
  existing `RulesEngine::Actions::*` classes.
- wait steps: mark run `waiting`, record resume_at, re-enqueue
  `ExecuteRunJob.set(wait_until:)` with the cursor pointing at the wait
  step's children. On resume the subject is reloaded; a deleted subject
  cancels the run.
- Loop protection: `triggered_by_run_id` ancestry (generalized
  CycleDetector) + hard depth cap (default 5) + per-(workflow, subject)
  concurrency: a new run for the same pair supersedes a `waiting` run only
  if trigger_config says so (default: both proceed, waits are independent).

### Catalog (Phases A–C)

`Workflows::Catalog` is the single machine-readable description of trigger
types (payload schema + filterable fields), condition fields per subject
type (reusing/expanding the rules registry), and action types (param
schemas, which subject types they accept). Served at
`GET /api/v1/workflows/catalog`; drives the builder UI.

### Actions (Phase C)

- Data (delegating to RulesEngine::Actions): assign_merchant,
  assign_category, assign_account, add_tag, set_memo, set_loan,
  mark_as_transfer.
- `notify`: creates a `Notification` (new model: household, title, body,
  severity, subject gid, read_at) surfaced in a notification-center API/UI;
  additionally POSTs to the household's configured notification webhook
  (e.g. ntfy) when present (`households.notification_webhook_url`).
- `fog_event`: publishes `fin.<type>` to fog's household event stream
  for HUD to route (on fog only; ACCESS.md has the shape). On fog every
  `Notification` is published there too, as `fin.notification`.
- `webhook`: POST JSON (event + subject snapshot + workflow context) to a
  workflow-configured URL. Guard rails: https only, 5s timeout, no
  redirects, response never interpolated, per-run outcome recorded.
- `create_issue`: templated title/body with subject interpolation.
- `trigger_sync`: enqueues PlaidSyncJob / CoinbaseSyncJob /
  MarketPriceSyncJob (allowlisted).
- `run_workflow`: dispatches another workflow against the same subject,
  inheriting the run ancestry for cycle protection.

### Monitors (Phase D)

Trigger type `monitor`: trigger_config holds a subject scope (model + static
filters) and a condition set. Edge-triggered: `workflow_monitor_states`
stores (workflow_id, subject) → last boolean; a run fires only on false→true.
Evaluated (a) when a relevant record event arrives for the subject model and
(b) by a periodic `Workflows::MonitorSweepJob` for time-dependent conditions.

### Migration (Phase E)

Each Rule → workflow: trigger `cash_transaction.created|updated|any`,
one branch step carrying the rule's conditions (match_all preserved), one
action step per rule action, priority → position. Rule folders → workflow
grouping. `rule_executions` history stays readable until cutover; the old
/rules endpoints are removed with the UI swap. Backup exporter/restorer
round-trips workflows with name-resolved params (same approach as rules).

### Builder UI (Phase F)

Catalog-driven React pages replacing /rules: workflows list (grouped,
active toggles, last-run status), tree builder (trigger picker with
filter rows; nested branch cards with condition editors; action rows with
param forms; wait rows; drag to reorder siblings), per-workflow run history
with step-level detail, notification center.

## Phase order and dependencies

A (events) → B (engine) → C (actions) → D (monitors) → E (migration) →
F (UI). Each phase lands green and committed; the rules engine keeps
working until E.
