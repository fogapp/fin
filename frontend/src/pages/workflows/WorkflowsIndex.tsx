import { useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { formatDistanceToNow } from "date-fns";
import { AlertTriangle, History, Play, Plus, Trash2, Workflow as WorkflowIcon } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { useHashParam } from "@/hooks/useHashParam";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { EmptyState } from "@/components/ui/empty-state";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs } from "@/components/ui/tabs";
import { toast } from "@/components/ui/toast";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { cn } from "@/lib/utils";
import { workflowTriggerLine } from "./draftSteps";
import type { WorkflowRunStatus, WorkflowSummary } from "@/api/types";
import { invalidate, keys } from "@/api/keys";

// ── Trigger families ──────────────────────────────────────────────────────────
// The smart axis: most households accumulate dozens of transaction rules that
// drown out the handful of schedules and monitors, so the page segments by
// what kind of thing a workflow reacts to.

type FamilyKey = "transactions" | "records" | "events" | "monitors" | "scheduled";
type Family = "all" | FamilyKey;

const FAMILIES: { key: FamilyKey; label: string }[] = [
  { key: "transactions", label: "Transaction rules" },
  { key: "records", label: "Record events" },
  { key: "events", label: "App events" },
  { key: "monitors", label: "Monitors" },
  { key: "scheduled", label: "Scheduled" },
];

// Rows shown per family section on the "All" tab before "Show all" takes over.
const ALL_TAB_SECTION_CAP = 5;

function familyOf(w: WorkflowSummary): FamilyKey {
  if (w.trigger_type === "schedule") return "scheduled";
  if (w.trigger_type === "monitor") return "monitors";
  if (w.trigger_type.startsWith("cash_transaction.") || w.trigger_type.startsWith("investment_transaction.")) {
    return "transactions";
  }
  if (/\.(created|updated|deleted|any)$/.test(w.trigger_type)) return "records";
  return "events";
}

// ── Workflows index ───────────────────────────────────────────────────────────

export function WorkflowsIndex() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const confirm = useConfirm();
  const { data: workflows = [], isLoading, isError, refetch } = useQuery(queries.workflows());

  const toggleActive = useMutation({
    mutationFn: ({ id, active }: { id: string; active: boolean }) =>
      api.patch(`/workflows/${id}`, { active }),
    onSuccess: () => invalidate(qc, keys.workflows),
  });

  async function runNow(w: WorkflowSummary) {
    const description = w.trigger_type === "monitor"
      ? "The monitor will be evaluated against all its subjects now."
      : w.trigger_type === "schedule"
        ? "It will run now instead of waiting for its schedule."
        : "It will run against existing records — matching records will get its actions applied.";
    if (!(await confirm({ title: `Run "${w.name}" now?`, description, confirmLabel: "Run" }))) return;
    try {
      await api.post(`/workflows/${w.id}/run_now`, {});
      invalidate(qc, keys.workflowRuns, keys.workflows);
    } catch {
      toast.error("Failed to queue the run");
    }
  }

  // Seeded workflows 422 on delete (and the button is hidden for them) — no
  // local onError, so the global MutationCache toasts whatever the server said
  // instead of failing silently.
  const deleteWorkflow = useMutation({
    mutationFn: (id: string) => api.delete(`/workflows/${id}`),
    onSuccess: () => invalidate(qc, keys.workflows),
  });

  async function handleDelete(w: WorkflowSummary) {
    if (await confirm({ title: `Delete "${w.name}"?`, destructive: true, confirmLabel: "Delete" })) {
      deleteWorkflow.mutate(w.id);
    }
  }

  // ── Filtering ───────────────────────────────────────────────────────────────

  const [rawFamily, setRawFamily] = useHashParam("family");
  const family: Family = (["all", ...FAMILIES.map((f) => f.key)] as Family[]).includes(rawFamily as Family)
    ? (rawFamily as Family)
    : "all";
  const setFamily = (f: Family) => setRawFamily(f === "all" ? null : f);

  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<"all" | "active" | "paused">("all");
  const [source, setSource] = useState<"all" | "mine" | "system">("all");
  const [sort, setSort] = useState<"default" | "name" | "recent">("default");

  const familyCounts = useMemo(() => {
    const counts = new Map<FamilyKey, number>();
    workflows.forEach((w) => {
      const f = familyOf(w);
      counts.set(f, (counts.get(f) ?? 0) + 1);
    });
    return counts;
  }, [workflows]);

  const q = search.trim().toLowerCase();
  const visible = useMemo(() => {
    let list = workflows;
    if (family !== "all") list = list.filter((w) => familyOf(w) === family);
    if (status !== "all") list = list.filter((w) => (status === "active" ? w.active : !w.active));
    if (source !== "all") list = list.filter((w) => (source === "system" ? !!w.seed_key : !w.seed_key));
    if (q) {
      list = list.filter((w) =>
        w.name.toLowerCase().includes(q) ||
        (w.description ?? "").toLowerCase().includes(q) ||
        workflowTriggerLine(w).toLowerCase().includes(q)
      );
    }
    if (sort === "name") list = [...list].sort((a, b) => a.name.localeCompare(b.name));
    if (sort === "recent") {
      list = [...list].sort((a, b) =>
        (b.last_run_at ? Date.parse(b.last_run_at) : 0) - (a.last_run_at ? Date.parse(a.last_run_at) : 0)
      );
    }
    return list;
  }, [workflows, family, status, source, q, sort]);

  const failing = visible.filter((w) => w.last_run_status === "failed");
  const healthy = visible.filter((w) => w.last_run_status !== "failed");
  const filtersApplied = family !== "all" || status !== "all" || source !== "all" || !!q;

  const rowProps = {
    onToggle: (w: WorkflowSummary) => toggleActive.mutate({ id: w.id, active: !w.active }),
    onDelete: handleDelete,
    onRun: runNow,
    deleting: deleteWorkflow.isPending,
  };

  // "All" tab with no search: group by family, capped per section. Anywhere
  // else (a family tab, or an active search): one flat list — never hide a match.
  const grouped = family === "all" && !q;

  return (
    <div className="flex h-full flex-col">
      <PageHeader
        title="Workflows"
        actions={[ { label: "New workflow", icon: Plus, onSelect: () => navigate("/workflows/new") } ]}
      />

      <div className="flex-1 overflow-y-auto p-6">
        {isError && <ErrorState title="Failed to load workflows" onRetry={refetch} />}

        {isLoading && (
          <div className="space-y-2">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-16 rounded-xl" />
            ))}
          </div>
        )}

        {!isLoading && !isError && workflows.length === 0 && (
          <EmptyState
            icon={WorkflowIcon}
            title="No workflows yet."
            description="Workflows react to events — branch on conditions, run actions, wait, and notify."
            action={
              <Button size="sm" onClick={() => navigate("/workflows/new")}>
                <Plus size={14} />
                New workflow
              </Button>
            }
            className="py-24"
          />
        )}

        {!isLoading && !isError && workflows.length > 0 && (
          <div className="mx-auto max-w-4xl space-y-4">
            {/* Search + manual filters */}
            <div className="flex flex-wrap items-center gap-2">
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Escape") setSearch(""); }}
                placeholder="Search workflows…"
                aria-label="Search workflows"
                className="h-8 w-64 text-sm"
              />
              <Select
                aria-label="Filter by status"
                value={status}
                onChange={(e) => setStatus(e.target.value as typeof status)}
                wrapperClassName="w-32 shrink-0"
                className="h-8 text-xs"
              >
                <option value="all">All statuses</option>
                <option value="active">Active</option>
                <option value="paused">Paused</option>
              </Select>
              <Select
                aria-label="Filter by source"
                value={source}
                onChange={(e) => setSource(e.target.value as typeof source)}
                wrapperClassName="w-32 shrink-0"
                className="h-8 text-xs"
              >
                <option value="all">All sources</option>
                <option value="mine">Mine</option>
                <option value="system">System</option>
              </Select>
              <Select
                aria-label="Sort workflows"
                value={sort}
                onChange={(e) => setSort(e.target.value as typeof sort)}
                wrapperClassName="w-36 shrink-0"
                className="h-8 text-xs"
              >
                <option value="default">Default order</option>
                <option value="name">Name</option>
                <option value="recent">Recently run</option>
              </Select>
            </div>

            {/* Smart segmentation by trigger family */}
            <Tabs
              size="sm"
              aria-label="Filter by trigger family"
              value={family}
              onChange={setFamily}
              options={[
                { value: "all" as Family, label: "All", count: workflows.length },
                ...FAMILIES.filter((f) => (familyCounts.get(f.key) ?? 0) > 0).map((f) => ({
                  value: f.key as Family,
                  label: f.label,
                  count: familyCounts.get(f.key),
                })),
              ]}
            />

            {/* Failed last run — always surfaced first */}
            {failing.length > 0 && (
              <section className="space-y-2">
                <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-warning">
                  <AlertTriangle size={12} />
                  Needs attention
                  <span className="font-normal">({failing.length})</span>
                </p>
                <div className="space-y-2">
                  {failing.map((w) => (
                    <WorkflowRow key={w.id} workflow={w} {...rowProps} />
                  ))}
                </div>
              </section>
            )}

            {grouped ? (
              <div className="space-y-6">
                {FAMILIES.map(({ key, label }) => {
                  const rows = healthy.filter((w) => familyOf(w) === key);
                  if (rows.length === 0) return null;
                  const capped = rows.slice(0, ALL_TAB_SECTION_CAP);
                  return (
                    <section key={key} className="space-y-2">
                      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                        {label}
                        <span className="ml-1.5 font-normal">({rows.length})</span>
                      </p>
                      <div className="space-y-2">
                        {capped.map((w) => (
                          <WorkflowRow key={w.id} workflow={w} {...rowProps} />
                        ))}
                      </div>
                      {rows.length > capped.length && (
                        <button
                          onClick={() => setFamily(key)}
                          className="rounded px-1 text-xs font-medium text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                        >
                          Show all {rows.length} →
                        </button>
                      )}
                    </section>
                  );
                })}
              </div>
            ) : (
              <div className="space-y-2">
                {healthy.map((w) => (
                  <WorkflowRow key={w.id} workflow={w} {...rowProps} />
                ))}
              </div>
            )}

            {visible.length === 0 && filtersApplied && (
              <EmptyState
                title="No workflows match the current filters."
                action={
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => { setSearch(""); setStatus("all"); setSource("all"); setFamily("all"); }}
                  >
                    Clear filters
                  </Button>
                }
                className="py-10"
              />
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Rows ──────────────────────────────────────────────────────────────────────

interface RowActions {
  onToggle: (w: WorkflowSummary) => void;
  onDelete: (w: WorkflowSummary) => void;
  onRun: (w: WorkflowSummary) => void;
  deleting: boolean;
}

const ROW_ICON_BUTTON =
  "shrink-0 rounded p-1 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:pointer-events-none disabled:opacity-50";

function WorkflowRow({ workflow: w, onToggle, onDelete, onRun, deleting }: RowActions & { workflow: WorkflowSummary }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border bg-card px-4 py-3">
      {/* Active toggle */}
      <button
        role="switch"
        aria-checked={w.active}
        aria-label={w.active ? `Deactivate ${w.name}` : `Activate ${w.name}`}
        onClick={() => onToggle(w)}
        className={cn(
          "relative h-5 w-9 shrink-0 rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
          w.active ? "bg-primary" : "bg-muted-foreground/30"
        )}
      >
        <span
          className={cn(
            "absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition-[left]",
            w.active ? "left-[18px]" : "left-0.5"
          )}
        />
      </button>

      {/* Name + trigger */}
      <Link to={`/workflows/${w.id}`} className="min-w-0 flex-1 group rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary">
        <p className="flex items-center gap-1.5 truncate text-sm font-medium group-hover:text-primary transition-colors">
          <span className="truncate">{w.name}</span>
          {w.seed_key && (
            <Badge variant="outline" className="shrink-0 font-normal text-muted-foreground">system</Badge>
          )}
        </p>
        <p className="truncate text-xs text-muted-foreground">
          {workflowTriggerLine(w)}
          {w.description ? ` — ${w.description}` : ""}
        </p>
      </Link>

      {/* Run stats */}
      <div className="flex shrink-0 items-center gap-2 text-xs text-muted-foreground">
        <span>{w.run_count} {w.run_count === 1 ? "run" : "runs"}</span>
        {w.last_run_status && (
          <>
            <RunStatusBadge status={w.last_run_status} />
            {w.last_run_at && <span>{formatDistanceToNow(new Date(w.last_run_at), { addSuffix: true })}</span>}
          </>
        )}
      </div>

      <button
        aria-label={`Run ${w.name} now`}
        title="Run now"
        onClick={() => onRun(w)}
        className={ROW_ICON_BUTTON}
      >
        <Play size={14} />
      </button>

      <Link
        to={`/workflows/${w.id}/runs`}
        aria-label={`View runs of ${w.name}`}
        className={ROW_ICON_BUTTON}
      >
        <History size={14} />
      </Link>

      {/* Seeded system workflows can't be deleted */}
      {!w.seed_key && (
        <button
          aria-label={`Delete ${w.name}`}
          disabled={deleting}
          onClick={() => onDelete(w)}
          className={cn(ROW_ICON_BUTTON, "hover:text-destructive")}
        >
          <Trash2 size={14} />
        </button>
      )}
    </div>
  );
}

export function RunStatusBadge({ status }: { status: WorkflowRunStatus | string }) {
  const variant =
    status === "completed" ? "success" :
    status === "failed" ? "destructive" :
    status === "running" || status === "waiting" || status === "pending" ? "default" :
    "outline";
  return <Badge variant={variant}>{status}</Badge>;
}
