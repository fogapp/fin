import { useState } from "react";
import { ArrowDown, ArrowUp, Clock, GitBranch, Plus, Trash2, Zap } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Tabs } from "@/components/ui/tabs";
import { ConditionRows } from "./ConditionRows";
import { ActionParamsForm } from "./ActionParamsForm";
import { actionLabel, addStep, moveStep, newStep, removeStep, updateStep } from "./draftSteps";
import type { DraftCondition, DraftStep } from "./draftSteps";
import type { RegistryField, WorkflowStepKind } from "@/api/types";

// ── Step tree builder ─────────────────────────────────────────────────────────
// Nested branch cards / action rows / wait rows. All mutations are FUNCTIONAL
// (they receive the current root inside the state setter) — computing from a
// render-closure snapshot loses concurrent edits when a stale handler (e.g. a
// blur commit) fires after a newer mutation.

interface TreeContext {
  mutate: (fn: (root: DraftStep[]) => DraftStep[]) => void;
  fields: Record<string, RegistryField>;
  actions: string[];
  workflowId?: string;
}

export function StepTree({
  steps, onChange, fields, actions, workflowId,
}: {
  steps: DraftStep[];
  onChange: (fn: (steps: DraftStep[]) => DraftStep[]) => void;
  fields: Record<string, RegistryField>;
  actions: string[];
  workflowId?: string;
}) {
  const ctx: TreeContext = { mutate: onChange, fields, actions, workflowId };
  return <StepList list={steps} parentKey={null} ctx={ctx} />;
}

function StepList({ list, parentKey, ctx }: { list: DraftStep[]; parentKey: number | null; ctx: TreeContext }) {
  function add(kind: WorkflowStepKind) {
    const step = newStep(kind);
    if (kind === "action") step.config = { action_type: ctx.actions[0] ?? "", params: {} };
    ctx.mutate((root) => addStep(root, parentKey, step));
  }

  return (
    <div className="space-y-2">
      {list.map((step, i) => (
        <StepNode key={step._key} step={step} siblings={list} index={i} ctx={ctx} />
      ))}
      <div className="flex items-center gap-3">
        <AddButton label="Branch" icon={GitBranch} onClick={() => add("branch")} />
        <AddButton label="Action" icon={Zap} onClick={() => add("action")} />
        <AddButton label="Wait" icon={Clock} onClick={() => add("wait")} />
      </div>
    </div>
  );
}

function AddButton({ label, icon: Icon, onClick }: { label: string; icon: typeof Plus; onClick: () => void }) {
  return (
    <Button
      variant="ghost"
      size="xs"
      onClick={onClick}
      className="gap-1.5 text-muted-foreground hover:text-foreground"
    >
      <Plus size={13} />
      <Icon size={13} />
      {label}
    </Button>
  );
}

// ── Node chrome ───────────────────────────────────────────────────────────────

const NODE_ICON_BUTTON =
  "rounded p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:opacity-30 disabled:pointer-events-none";

function StepNode({ step, siblings, index, ctx }: { step: DraftStep; siblings: DraftStep[]; index: number; ctx: TreeContext }) {
  const prev = siblings[index - 1];
  const next = siblings[index + 1];
  // Waits stay last among siblings — moves may not cross the wait boundary.
  const canMoveUp = index > 0 && !(step.kind === "wait" && prev?.kind !== "wait");
  const canMoveDown = index < siblings.length - 1 && !(step.kind !== "wait" && next?.kind === "wait");

  const controls = (
    <div className="flex shrink-0 items-center gap-0.5">
      <button
        aria-label="Move step up"
        disabled={!canMoveUp}
        onClick={() => ctx.mutate((root) => moveStep(root, step._key, -1))}
        className={NODE_ICON_BUTTON}
      >
        <ArrowUp size={13} />
      </button>
      <button
        aria-label="Move step down"
        disabled={!canMoveDown}
        onClick={() => ctx.mutate((root) => moveStep(root, step._key, 1))}
        className={NODE_ICON_BUTTON}
      >
        <ArrowDown size={13} />
      </button>
      <button
        aria-label="Remove step"
        onClick={() => ctx.mutate((root) => removeStep(root, step._key))}
        className="rounded p-1 text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <Trash2 size={14} />
      </button>
    </div>
  );

  if (step.kind === "branch") return <BranchCard step={step} prev={prev} ctx={ctx} controls={controls} />;
  if (step.kind === "wait") return <WaitCard step={step} ctx={ctx} controls={controls} />;
  return <ActionRow step={step} ctx={ctx} controls={controls} />;
}

// ── Branch ────────────────────────────────────────────────────────────────────

function BranchCard({ step, prev, ctx, controls }: { step: DraftStep; prev?: DraftStep; ctx: TreeContext; controls: React.ReactNode }) {
  const isElse = step.config.else === true;
  const matchAll = step.config.match_all !== false;
  const conditions = Array.isArray(step.config.conditions) ? (step.config.conditions as DraftCondition[]) : [];
  const label = isElse ? "Else" : prev?.kind === "branch" ? "Else if" : "If";

  function patchConfig(changes: Record<string, unknown>) {
    ctx.mutate((root) => updateStep(root, step._key, { config: { ...step.config, ...changes } }));
  }

  return (
    <div className="rounded-xl border bg-card p-3 space-y-3">
      <div className="flex items-center gap-3">
        <span className="flex items-center gap-1.5 text-sm font-medium">
          <GitBranch size={14} className="text-muted-foreground" />
          {label}
        </span>

        {!isElse && (
          <Tabs
            size="sm"
            value={matchAll ? "all" : "any"}
            onChange={(v) => patchConfig({ match_all: v === "all" })}
            options={[{ value: "all", label: "ALL" }, { value: "any", label: "ANY" }]}
          />
        )}

        <label className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer select-none">
          <Checkbox
            checked={isElse}
            onChange={(e) =>
              ctx.mutate((root) => updateStep(root, step._key, {
                config: e.target.checked ? { else: true } : { match_all: true, conditions: [] },
              }))
            }
            className="h-3.5 w-3.5"
          />
          Else branch
        </label>

        <div className="flex-1" />
        {controls}
      </div>

      {isElse ? (
        <p className="text-sm text-muted-foreground">Runs when no earlier branch matched.</p>
      ) : (
        <ConditionRows
          conditions={conditions}
          onChange={(cs) => patchConfig({ conditions: cs })}
          fields={ctx.fields}
          matchAll={matchAll}
        />
      )}

      <div className="border-l-2 border-border/70 pl-4 pt-1">
        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Then</p>
        <StepList list={step.children} parentKey={step._key} ctx={ctx} />
      </div>
    </div>
  );
}

// ── Wait ──────────────────────────────────────────────────────────────────────

const UNIT_SECONDS = { minutes: 60, hours: 3600, days: 86400 } as const;
type WaitUnit = keyof typeof UNIT_SECONDS;

function initialUnit(seconds: number): WaitUnit {
  if (seconds > 0 && seconds % UNIT_SECONDS.days === 0) return "days";
  if (seconds > 0 && seconds % UNIT_SECONDS.hours === 0) return "hours";
  return "minutes";
}

function WaitCard({ step, ctx, controls }: { step: DraftStep; ctx: TreeContext; controls: React.ReactNode }) {
  const seconds = Number(step.config.duration_seconds ?? 0);
  const [unit, setUnit] = useState<WaitUnit>(() => initialUnit(seconds));
  const value = Math.round(seconds / UNIT_SECONDS[unit]);

  function setDuration(nextValue: number, nextUnit: WaitUnit) {
    ctx.mutate((root) => updateStep(root, step._key, {
      config: { ...step.config, duration_seconds: Math.max(0, nextValue) * UNIT_SECONDS[nextUnit] },
    }));
  }

  return (
    <div className="rounded-xl border bg-card p-3 space-y-3">
      <div className="flex items-center gap-3">
        <span className="flex items-center gap-1.5 text-sm font-medium">
          <Clock size={14} className="text-muted-foreground" />
          Wait
        </span>

        <Input
          type="number"
          min={0}
          aria-label="Wait duration"
          value={value}
          onChange={(e) => setDuration(Number(e.target.value), unit)}
          className="w-20 tabular-nums"
        />
        <Select
          aria-label="Wait unit"
          value={unit}
          onChange={(e) => {
            const u = e.target.value as WaitUnit;
            setUnit(u);
            setDuration(value, u);
          }}
          wrapperClassName="w-28"
        >
          {Object.keys(UNIT_SECONDS).map((u) => <option key={u} value={u}>{u}</option>)}
        </Select>

        <div className="flex-1" />
        {controls}
      </div>

      <div className="border-l-2 border-border/70 pl-4 pt-1">
        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">After the delay</p>
        <StepList list={step.children} parentKey={step._key} ctx={ctx} />
      </div>
    </div>
  );
}

// ── Action ────────────────────────────────────────────────────────────────────

function ActionRow({ step, ctx, controls }: { step: DraftStep; ctx: TreeContext; controls: React.ReactNode }) {
  const actionType = String(step.config.action_type ?? "");
  const params = (step.config.params ?? {}) as Record<string, unknown>;
  const stopOnError = step.config.stop_on_error === true;

  function patchConfig(changes: Record<string, unknown>) {
    ctx.mutate((root) => updateStep(root, step._key, { config: { ...step.config, ...changes } }));
  }

  return (
    <div className="rounded-xl border bg-card p-3 space-y-2">
      <div className="flex items-start gap-2">
        <Select
          aria-label="Action type"
          value={actionType}
          onChange={(e) => patchConfig({ action_type: e.target.value, params: {} })}
          wrapperClassName="w-44 shrink-0"
        >
          {ctx.actions.map((a) => <option key={a} value={a}>{actionLabel(a)}</option>)}
        </Select>

        <ActionParamsForm
          actionType={actionType}
          params={params}
          onChange={(p) => patchConfig({ params: p })}
          workflowId={ctx.workflowId}
        />

        {controls}
      </div>

      <label className="flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer select-none">
        <Checkbox
          checked={stopOnError}
          onChange={(e) => {
            const config = { ...step.config };
            if (e.target.checked) config.stop_on_error = true;
            else delete config.stop_on_error;
            ctx.mutate((root) => updateStep(root, step._key, { config }));
          }}
          className="h-3.5 w-3.5"
        />
        Stop workflow if this action errors
      </label>
    </div>
  );
}
