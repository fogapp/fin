import { useState } from "react";
import { useNavigate, useParams, useLocation } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, History, Play, Trash2 } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { useConfirm } from "@/components/ui/confirm";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs } from "@/components/ui/tabs";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { cn } from "@/lib/utils";
import { ConditionRows } from "./ConditionRows";
import { StepTree } from "./StepTree";
import {
  MONITOR_TRIGGER, SCHEDULE_TRIGGER, fieldsForTrigger, fromApiSteps, hasDataAction,
  hasUnguardedDataAction, humanize, isRecordEvent, monitorSubjects, toPayload,
  triggerGroups, triggerLabel,
} from "./draftSteps";
import type { DraftCondition, DraftStep } from "./draftSteps";
import type { WorkflowCatalog, WorkflowDetail, WorkflowStepInput } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Entry point ───────────────────────────────────────────────────────────────

/** Draft seed passed through router state (e.g. the quick-automation modal's
 *  "Advanced" link) — only consumed when creating a new workflow. */
export interface WorkflowPrefill {
  name?: string;
  trigger_type?: string;
  steps?: WorkflowStepInput[];
}

export function WorkflowEditor() {
  const { id } = useParams<{ id: string }>();
  const location = useLocation();
  const isNew = !id;

  const catalogQuery = useQuery(queries.workflowCatalog());
  const workflowQuery = useQuery({ ...queries.workflow(id!), enabled: !isNew });
  const catalog = catalogQuery.data;
  const workflow = workflowQuery.data;

  if (catalogQuery.isError) {
    return <ErrorState title="Failed to load the workflow catalog" onRetry={catalogQuery.refetch} />;
  }
  if (!isNew && workflowQuery.isError) {
    return <ErrorState title="Failed to load the workflow" onRetry={workflowQuery.refetch} />;
  }
  if (!catalog || (!isNew && workflowQuery.isLoading)) return <LoadingState />;
  if (!isNew && !workflow) return <EmptyState title="Workflow not found." />;

  const prefill = isNew ? (location.state as { prefill?: WorkflowPrefill } | null)?.prefill ?? null : null;

  return <EditorForm key={workflow?.id ?? "new"} catalog={catalog} workflow={workflow ?? null} prefill={prefill} />;
}

function LoadingState() {
  return (
    <div className="mx-auto max-w-3xl space-y-6 p-6">
      <Skeleton className="h-6 w-40" />
      <Skeleton className="h-28 rounded-xl" />
      <Skeleton className="h-32 rounded-xl" />
      <Skeleton className="h-24 rounded-xl" />
    </div>
  );
}

// ── Editor form ───────────────────────────────────────────────────────────────

function EditorForm({ catalog, workflow, prefill }: {
  catalog: WorkflowCatalog;
  workflow: WorkflowDetail | null;
  prefill?: WorkflowPrefill | null;
}) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const confirm = useConfirm();
  const isNew = workflow === null;

  const groups = triggerGroups(catalog);
  const subjects = monitorSubjects(catalog);
  const config = workflow?.trigger_config ?? {};

  const [name, setName] = useState(workflow?.name ?? prefill?.name ?? "");
  const [description, setDescription] = useState(workflow?.description ?? "");
  const [active, setActive] = useState(workflow?.active ?? true);
  const [triggerType, setTriggerType] = useState(
    workflow?.trigger_type ?? prefill?.trigger_type ?? groups.record[0] ?? ""
  );
  const [changedFields, setChangedFields] = useState<string[]>(
    Array.isArray(config.changed_fields) ? (config.changed_fields as string[]).map(String) : []
  );
  const [monitorSubject, setMonitorSubject] = useState(
    typeof config.subject === "string" ? config.subject : (subjects[0] ?? "")
  );
  const [monitorMatchAll, setMonitorMatchAll] = useState(config.match_all !== false);
  const [monitorConditions, setMonitorConditions] = useState<DraftCondition[]>(
    Array.isArray(config.conditions) ? (config.conditions as DraftCondition[]) : []
  );
  const [schedule, setSchedule] = useState<ScheduleDraft>(() => ({
    frequency: isScheduleFrequency(config.frequency) ? config.frequency : "daily",
    everyHours: typeof config.every_hours === "number" ? config.every_hours : 1,
    at: typeof config.at === "string" ? config.at : "05:00",
    dayOfWeek: typeof config.day_of_week === "number" ? config.day_of_week : 1,
    dayOfMonth: typeof config.day_of_month === "number" ? config.day_of_month : 1,
  }));
  const [steps, setSteps] = useState<DraftStep[]>(() => fromApiSteps(workflow?.steps ?? prefill?.steps ?? []));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isMonitor = triggerType === MONITOR_TRIGGER;
  const isSchedule = triggerType === SCHEDULE_TRIGGER;
  const isUpdated = triggerType.endsWith(".updated");
  const subjectFields = fieldsForTrigger(catalog, triggerType, monitorSubject);

  // Data-mutating actions with no branch conditions above them rewrite every
  // triggering record — warn (don't block; it's occasionally intentional).
  // Monitor conditions in the trigger config count as a guard too. Scheduled
  // runs have no subject, so the muted skip hint replaces the amber warning.
  const unguarded = !isSchedule
    && hasUnguardedDataAction(steps)
    && !(isMonitor && monitorConditions.length > 0);
  const scheduleSkipsData = isSchedule && hasDataAction(steps);
  const subjectLabel = isMonitor
    ? humanize(monitorSubject || "record")
    : isRecordEvent(triggerType)
      ? humanize(triggerType.replace(/\.(created|updated|deleted|any)$/, ""))
      : "record";

  function buildTriggerConfig(): Record<string, unknown> {
    if (isMonitor) return { subject: monitorSubject, match_all: monitorMatchAll, conditions: monitorConditions };
    if (isSchedule) return scheduleTriggerConfig(schedule);
    if (isUpdated && changedFields.length > 0) return { changed_fields: changedFields };
    return {};
  }

  const [runNotice, setRunNotice] = useState<string | null>(null);
  const [running, setRunning] = useState(false);

  async function handleRunNow() {
    if (!workflow) return;
    const description = workflow.trigger_type === "monitor"
      ? "The monitor will be evaluated against all its subjects. Subjects already in the triggered state will not re-fire."
      : workflow.trigger_type === "schedule"
        ? "It will run now instead of waiting for its schedule."
        : "It will run against existing records — records matching its conditions will get the workflow's actions applied.";
    if (!(await confirm({ title: "Run this workflow now?", description, confirmLabel: "Run" }))) return;
    setRunning(true);
    try {
      const res = await api.post<{ status: string; mode: string }>(`/workflows/${workflow.id}/run_now`, {});
      setRunNotice(res.mode === "monitor" ? "Monitor evaluation queued" : "Run queued — see View runs for results");
      setTimeout(() => setRunNotice(null), 4000);
    } catch (e) {
      setRunNotice((e as Error).message);
      setTimeout(() => setRunNotice(null), 6000);
    } finally {
      setRunning(false);
    }
  }

  async function handleSave() {
    setSaving(true);
    setError(null);
    const payload = {
      name: name.trim(),
      description: description.trim() || null,
      trigger_type: triggerType,
      active,
      trigger_config: buildTriggerConfig(),
      steps: toPayload(steps),
    };
    try {
      if (isNew) {
        const created = await api.post<WorkflowDetail>("/workflows", payload);
        invalidate(qc, keys.workflows);
        navigate(`/workflows/${created.id}`);
      } else {
        await api.patch(`/workflows/${workflow.id}`, payload);
        invalidate(qc, keys.workflows);
      }
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!workflow) return;
    if (!(await confirm({ title: "Delete this workflow?", destructive: true, confirmLabel: "Delete" }))) return;
    try {
      await api.delete(`/workflows/${workflow.id}`);
      invalidate(qc, keys.workflows);
      navigate("/workflows");
    } catch (e) {
      setError((e as Error).message);
    }
  }

  return (
    <div className="flex h-full flex-col">
      <PageHeader
        title={isNew ? "New Workflow" : (workflow.name || "Unnamed Workflow")}
        back={{ to: "/workflows" }}
        actions={isNew ? [] : [
          { label: running ? "Queuing…" : "Run now", icon: Play, onSelect: handleRunNow, disabled: running },
          { label: "View runs", icon: History, onSelect: () => navigate(`/workflows/${workflow.id}/runs`) },
          ...(!workflow.seed_key ? [ {
            label: "Delete workflow",
            icon: Trash2,
            destructive: true,
            onSelect: handleDelete,
          } ] : []),
        ]}
      >
        {!isNew && runNotice && <span className="text-xs text-muted-foreground">{runNotice}</span>}
        <label className="flex items-center gap-2 text-sm cursor-pointer select-none">
          <Checkbox checked={active} onChange={(e) => setActive(e.target.checked)} />
          Active
        </label>
        <Button size="sm" onClick={handleSave} disabled={saving || !name.trim()} title={!name.trim() ? "Name the workflow before saving" : undefined}>
          {saving ? "Saving…" : isNew ? "Create workflow" : "Save"}
        </Button>
      </PageHeader>

      {error && (
        <div className="flex items-center justify-between border-b bg-destructive/10 px-6 py-2">
          <p className="text-sm text-destructive">{error}</p>
          <Button variant="ghost" size="xs" onClick={() => setError(null)} className="text-muted-foreground hover:text-foreground">
            Dismiss
          </Button>
        </div>
      )}

      {unguarded && (
        <div role="alert" className="flex items-center gap-2 border-b border-warning/30 bg-warning/10 px-6 py-2 text-sm text-warning">
          <AlertTriangle size={15} className="shrink-0" />
          <p>
            This workflow has no conditions guarding its data changes — it will modify
            every {subjectLabel} that triggers it.
          </p>
        </div>
      )}

      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl space-y-8 p-6">
          {/* Meta */}
          <div className="rounded-xl border bg-card p-5 space-y-3">
            <Input
              aria-label="Workflow name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Workflow name"
            />
            <Input
              aria-label="Description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Description (optional)"
            />
          </div>

          {/* Trigger */}
          <section className="space-y-3">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Trigger</p>
            <div className="rounded-xl border bg-card p-5 space-y-4">
              <TriggerSelect
                value={triggerType}
                groups={groups}
                onChange={(t) => { setTriggerType(t); setChangedFields([]); }}
              />

              {isUpdated && !isSchedule && (
                <ChangedFieldsPicker
                  fields={Object.keys(subjectFields)}
                  selected={changedFields}
                  onChange={setChangedFields}
                />
              )}

              {isSchedule && (
                <div className="space-y-3">
                  <ScheduleConfigEditor value={schedule} onChange={setSchedule} />
                  {scheduleSkipsData && (
                    <p className="text-xs text-muted-foreground">
                      Scheduled runs have no subject — data actions will be skipped.
                    </p>
                  )}
                </div>
              )}

              {isMonitor && (
                <div className="space-y-3">
                  <div className="flex flex-wrap items-center gap-3 text-sm">
                    <Label htmlFor="monitor-subject">Watch</Label>
                    <Select
                      id="monitor-subject"
                      value={monitorSubject}
                      onChange={(e) => { setMonitorSubject(e.target.value); setMonitorConditions([]); }}
                      wrapperClassName="w-56"
                    >
                      {subjects.map((s) => <option key={s} value={s}>{humanize(s)}</option>)}
                    </Select>
                    <Label>Match</Label>
                    <Tabs
                      size="sm"
                      value={monitorMatchAll ? "all" : "any"}
                      onChange={(v) => setMonitorMatchAll(v === "all")}
                      options={[{ value: "all", label: "ALL" }, { value: "any", label: "ANY" }]}
                    />
                  </div>
                  <ConditionRows
                    conditions={monitorConditions}
                    onChange={setMonitorConditions}
                    fields={subjectFields}
                    matchAll={monitorMatchAll}
                  />
                  <p className="text-xs text-muted-foreground">
                    The workflow runs when a watched record starts matching these conditions.
                  </p>
                </div>
              )}
            </div>
          </section>

          {/* Steps */}
          <section className="space-y-3">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Steps</p>
            <StepTree
              steps={steps}
              onChange={setSteps}
              fields={subjectFields}
              actions={catalog.actions}
              workflowId={workflow?.id}
            />
          </section>
        </div>
      </div>
    </div>
  );
}

// ── Schedule config ───────────────────────────────────────────────────────────

interface ScheduleDraft {
  frequency: "hourly" | "daily" | "weekly" | "monthly";
  everyHours: number;
  at: string;
  dayOfWeek: number;
  dayOfMonth: number;
}

function isScheduleFrequency(v: unknown): v is ScheduleDraft["frequency"] {
  return v === "hourly" || v === "daily" || v === "weekly" || v === "monthly";
}

/** Serialize the draft into the backend's exact trigger_config shapes. */
function scheduleTriggerConfig(s: ScheduleDraft): Record<string, unknown> {
  switch (s.frequency) {
    case "hourly":  return { frequency: "hourly", every_hours: s.everyHours };
    case "daily":   return { frequency: "daily", at: s.at };
    case "weekly":  return { frequency: "weekly", at: s.at, day_of_week: s.dayOfWeek };
    case "monthly": return { frequency: "monthly", at: s.at, day_of_month: s.dayOfMonth };
  }
}

const WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

function ScheduleConfigEditor({ value, onChange }: {
  value: ScheduleDraft;
  onChange: (s: ScheduleDraft) => void;
}) {
  function patch(changes: Partial<ScheduleDraft>) {
    onChange({ ...value, ...changes });
  }

  return (
    <div className="flex flex-wrap items-center gap-3 text-sm">
      <Label htmlFor="schedule-frequency">Runs</Label>
      <Select
        id="schedule-frequency"
        aria-label="Frequency"
        value={value.frequency}
        onChange={(e) => patch({ frequency: e.target.value as ScheduleDraft["frequency"] })}
        wrapperClassName="w-32"
      >
        <option value="hourly">Hourly</option>
        <option value="daily">Daily</option>
        <option value="weekly">Weekly</option>
        <option value="monthly">Monthly</option>
      </Select>

      {value.frequency === "hourly" && (
        <>
          <Label htmlFor="schedule-every-hours">every</Label>
          <Input
            id="schedule-every-hours"
            aria-label="Every N hours"
            type="number"
            min={1}
            max={24}
            value={value.everyHours}
            onChange={(e) => patch({ everyHours: Math.min(24, Math.max(1, Number(e.target.value) || 1)) })}
            className="w-16 tabular-nums"
          />
          <span className="text-xs text-muted-foreground">hour{value.everyHours === 1 ? "" : "s"}</span>
        </>
      )}

      {value.frequency === "weekly" && (
        <>
          <Label htmlFor="schedule-day-of-week">on</Label>
          <Select
            id="schedule-day-of-week"
            aria-label="Day of week"
            value={value.dayOfWeek}
            onChange={(e) => patch({ dayOfWeek: Number(e.target.value) })}
            wrapperClassName="w-36"
          >
            {WEEKDAYS.map((d, i) => <option key={d} value={i + 1}>{d}</option>)}
          </Select>
        </>
      )}

      {value.frequency === "monthly" && (
        <>
          <Label htmlFor="schedule-day-of-month">on day</Label>
          <Input
            id="schedule-day-of-month"
            aria-label="Day of month"
            type="number"
            min={1}
            max={28}
            value={value.dayOfMonth}
            onChange={(e) => patch({ dayOfMonth: Math.min(28, Math.max(1, Number(e.target.value) || 1)) })}
            className="w-16 tabular-nums"
          />
        </>
      )}

      {value.frequency !== "hourly" && (
        <>
          <Label htmlFor="schedule-at">at</Label>
          <Input
            id="schedule-at"
            aria-label="Time"
            type="time"
            value={value.at}
            onChange={(e) => { if (e.target.value) patch({ at: e.target.value }); }}
            className="w-auto tabular-nums"
          />
        </>
      )}
    </div>
  );
}

// ── Trigger select ────────────────────────────────────────────────────────────

function TriggerSelect({
  value, groups, onChange,
}: {
  value: string;
  groups: { record: string[]; app: string[]; monitor: boolean; schedule: boolean };
  onChange: (t: string) => void;
}) {
  return (
    <Select aria-label="Trigger" value={value} onChange={(e) => onChange(e.target.value)}>
      <optgroup label="Record events">
        {groups.record.map((t) => <option key={t} value={t}>{triggerLabel(t)}</option>)}
      </optgroup>
      <optgroup label="App events">
        {groups.app.map((t) => <option key={t} value={t}>{triggerLabel(t)}</option>)}
      </optgroup>
      {groups.monitor && (
        <optgroup label="Monitors">
          <option value={MONITOR_TRIGGER}>{triggerLabel(MONITOR_TRIGGER)}</option>
        </optgroup>
      )}
      {groups.schedule && (
        <optgroup label="Schedules">
          <option value={SCHEDULE_TRIGGER}>{triggerLabel(SCHEDULE_TRIGGER)}</option>
        </optgroup>
      )}
    </Select>
  );
}

// ── Changed-fields picker ─────────────────────────────────────────────────────

function ChangedFieldsPicker({
  fields, selected, onChange,
}: {
  fields: string[];
  selected: string[];
  onChange: (fields: string[]) => void;
}) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs text-muted-foreground">
        Only run when one of these fields changed (leave empty for any change):
      </p>
      <div className="flex flex-wrap gap-1.5">
        {fields.map((f) => {
          const on = selected.includes(f);
          return (
            <button
              key={f}
              type="button"
              aria-pressed={on}
              onClick={() => onChange(on ? selected.filter((x) => x !== f) : [...selected, f])}
              className={cn(
                "rounded-full border px-2 py-0.5 text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                on ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground hover:bg-accent"
              )}
            >
              {humanize(f)}
            </button>
          );
        })}
        {fields.length === 0 && <span className="text-xs text-muted-foreground">No fields available</span>}
      </div>
    </div>
  );
}
