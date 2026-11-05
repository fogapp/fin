import { formatDistanceToNow } from "date-fns";
import type { Workflow, WorkflowCatalog, WorkflowStep, WorkflowStepInput, WorkflowStepKind } from "@/api/types";

// ── Draft step tree ───────────────────────────────────────────────────────────
// The editor works on a draft copy of the step tree: every node carries a
// synthetic _key (React list key + mutation handle). On save the tree is
// stripped back to {kind, config, children} — the backend replaces the whole
// tree wholesale, so persisted ids are irrelevant.

export interface DraftCondition {
  field: string;
  operator: string;
  value: string;
}

export interface DraftStep {
  _key: number;
  kind: WorkflowStepKind;
  config: Record<string, unknown>;
  children: DraftStep[];
}

let seq = 0;
export function nextKey(): number {
  seq += 1;
  return seq;
}

export function fromApiSteps(steps: (WorkflowStep | WorkflowStepInput)[]): DraftStep[] {
  return steps.map((s) => ({
    _key: nextKey(),
    kind: s.kind,
    config: { ...s.config },
    children: fromApiSteps(s.children ?? []),
  }));
}

export function toPayload(steps: DraftStep[]): WorkflowStepInput[] {
  return steps.map((s) => ({ kind: s.kind, config: s.config, children: toPayload(s.children) }));
}

/** Waits run last among their siblings — stable-partition so every list keeps
 *  its non-wait steps (in order) ahead of its waits (in order). */
export function waitsLast(steps: DraftStep[]): DraftStep[] {
  return [...steps.filter((s) => s.kind !== "wait"), ...steps.filter((s) => s.kind === "wait")];
}

export function newStep(kind: WorkflowStepKind): DraftStep {
  const config: Record<string, unknown> =
    kind === "branch" ? { match_all: true, conditions: [] } :
    kind === "action" ? { action_type: "", params: {} } :
    { duration_seconds: 3600 };
  return { _key: nextKey(), kind, config, children: [] };
}

/** Apply fn to the sibling list containing the node keyed `key` (or the root
 *  list when key is null), returning a structurally-shared new tree. */
function mapList(steps: DraftStep[], fn: (list: DraftStep[]) => DraftStep[], containsKey: number | null): DraftStep[] {
  if (containsKey === null || steps.some((s) => s._key === containsKey)) return fn(steps);
  return steps.map((s) =>
    subtreeContains(s, containsKey) ? { ...s, children: mapList(s.children, fn, containsKey) } : s
  );
}

function subtreeContains(step: DraftStep, key: number): boolean {
  return step.children.some((c) => c._key === key || subtreeContains(c, key));
}

export function updateStep(steps: DraftStep[], key: number, patch: Partial<Pick<DraftStep, "config" | "kind">>): DraftStep[] {
  return steps.map((s) =>
    s._key === key ? { ...s, ...patch } : { ...s, children: updateStep(s.children, key, patch) }
  );
}

export function removeStep(steps: DraftStep[], key: number): DraftStep[] {
  return steps
    .filter((s) => s._key !== key)
    .map((s) => ({ ...s, children: removeStep(s.children, key) }));
}

/** Insert under the parent keyed `parentKey` (root list when null), keeping
 *  waits at the end of the sibling list. */
export function addStep(steps: DraftStep[], parentKey: number | null, step: DraftStep): DraftStep[] {
  if (parentKey === null) return waitsLast([...steps, step]);
  return steps.map((s) =>
    s._key === parentKey
      ? { ...s, children: waitsLast([...s.children, step]) }
      : { ...s, children: addStep(s.children, parentKey, step) }
  );
}

/** Swap the node with its previous/next sibling; the waits-last invariant is
 *  re-imposed afterwards, so cross-partition swaps are no-ops. */
export function moveStep(steps: DraftStep[], key: number, dir: -1 | 1): DraftStep[] {
  return mapList(steps, (list) => {
    const i = list.findIndex((s) => s._key === key);
    const j = i + dir;
    if (i < 0 || j < 0 || j >= list.length) return list;
    const next = [...list];
    [next[i], next[j]] = [next[j], next[i]];
    return waitsLast(next);
  }, key);
}

// ── Safety checks ─────────────────────────────────────────────────────────────

/** Action types that mutate records (vs. side-effect-only ones like notify). */
export const DATA_ACTION_TYPES = new Set([
  "assign_merchant", "assign_category", "assign_account",
  "add_tag", "set_memo", "set_loan", "mark_as_transfer",
]);

function guardsChildren(step: DraftStep): boolean {
  return step.kind === "branch"
    && Array.isArray(step.config.conditions)
    && (step.config.conditions as unknown[]).length > 0;
}

/** True when the tree contains any data-mutating action at all — scheduled
 *  runs have no subject, so these steps are skipped at runtime. */
export function hasDataAction(steps: DraftStep[]): boolean {
  return steps.some((s) =>
    (s.kind === "action" &&
      typeof s.config.action_type === "string" &&
      DATA_ACTION_TYPES.has(s.config.action_type)) ||
    hasDataAction(s.children)
  );
}

/** True when some data-mutating action is not nested under any branch with a
 *  non-empty conditions list — i.e. it would run for every triggering record. */
export function hasUnguardedDataAction(steps: DraftStep[], guarded = false): boolean {
  return steps.some((s) => {
    if (
      !guarded &&
      s.kind === "action" &&
      typeof s.config.action_type === "string" &&
      DATA_ACTION_TYPES.has(s.config.action_type)
    ) {
      return true;
    }
    return hasUnguardedDataAction(s.children, guarded || guardsChildren(s));
  });
}

// ── Trigger helpers ───────────────────────────────────────────────────────────

export const MONITOR_TRIGGER = "monitor";
export const SCHEDULE_TRIGGER = "schedule";
const RECORD_EVENT_RE = /\.(created|updated|deleted|any)$/;

export function isRecordEvent(type: string): boolean {
  return RECORD_EVENT_RE.test(type);
}

export function triggerGroups(catalog: WorkflowCatalog): { record: string[]; app: string[]; monitor: boolean; schedule: boolean } {
  const types = catalog.triggers.map((t) => t.type);
  return {
    record: types.filter(isRecordEvent),
    app: types.filter((t) => !isRecordEvent(t) && t !== MONITOR_TRIGGER && t !== SCHEDULE_TRIGGER),
    monitor: types.includes(MONITOR_TRIGGER),
    schedule: types.includes(SCHEDULE_TRIGGER),
  };
}

export function humanize(s: string): string {
  return s.replace(/[_.]/g, " ");
}

/** Action types whose humanized name wouldn't say what they do. */
const ACTION_LABELS: Record<string, string> = { fog_event: "send to HUD" };

export function actionLabel(type: string): string {
  return ACTION_LABELS[type] ?? humanize(type);
}

export function triggerLabel(type: string): string {
  if (type === MONITOR_TRIGGER) return "Monitor (threshold watch)";
  if (type === SCHEDULE_TRIGGER) return "On a schedule";
  const text = humanize(type);
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/** Record-model keys available as monitor subjects, from the catalog's
 *  `<key>.updated` entries (whose fields also drive the condition editor). */
export function monitorSubjects(catalog: WorkflowCatalog): string[] {
  return catalog.triggers
    .filter((t) => t.type.endsWith(".updated"))
    .map((t) => t.type.replace(/\.updated$/, ""));
}

/** The catalog fields for a trigger; monitors resolve via their subject key. */
export function fieldsForTrigger(catalog: WorkflowCatalog, triggerType: string, monitorSubject?: string) {
  const type = triggerType === MONITOR_TRIGGER ? `${monitorSubject}.updated` : triggerType;
  return catalog.triggers.find((t) => t.type === type)?.fields ?? {};
}

export function triggerSummary(triggerType: string, triggerConfig: Record<string, unknown>): string {
  if (triggerType === MONITOR_TRIGGER) {
    const subject = typeof triggerConfig.subject === "string" ? triggerConfig.subject : null;
    return subject ? `Monitor · ${humanize(subject)}` : "Monitor";
  }
  if (triggerType === SCHEDULE_TRIGGER) return "Schedule";
  return triggerLabel(triggerType);
}

/** Trigger line for a workflow row: scheduled workflows show the server's
 *  schedule summary plus a relative next-run time; everything else derives
 *  from the trigger config. */
export function workflowTriggerLine(w: Workflow): string {
  if (w.trigger_type === SCHEDULE_TRIGGER && w.schedule_summary) {
    const next = w.next_scheduled_at
      ? ` · next ${formatDistanceToNow(new Date(w.next_scheduled_at), { addSuffix: true })}`
      : "";
    return `${w.schedule_summary}${next}`;
  }
  return triggerSummary(w.trigger_type, w.trigger_config);
}
