import { useState } from "react";
import { useParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { formatDistanceToNow } from "date-fns";
import { ChevronDown, ChevronRight, Layers, Undo2 } from "lucide-react";
import { queries } from "@/api/queries";
import { mutations } from "@/api/mutations";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useConfirm } from "@/components/ui/confirm";
import { EmptyState } from "@/components/ui/empty-state";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/toast";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { RunStatusBadge } from "./WorkflowsIndex";
import { humanize } from "./draftSteps";
import { cn } from "@/lib/utils";
import type { WorkflowRun, WorkflowRunGroup, WorkflowRunRevertResult, WorkflowRunStatus } from "@/api/types";
import { invalidate, keys } from "@/api/keys";
import { Pagination } from "@/components/ui/pagination";

// ── Workflow runs ─────────────────────────────────────────────────────────────

const STATUSES = ["pending", "running", "waiting", "completed", "failed", "cancelled"];

const GROUP_RUNS_PER_PAGE = 50;

const REVERT_ALL_DESCRIPTION =
  "Values the workflow changed will be restored. " +
  "Values you have edited since are kept. " +
  "Notifications and webhooks cannot be undone.";

const REVERT_RUN_DESCRIPTION =
  "Values the workflow changed will be restored. Values you have edited since are kept.";

function revertSummary({ reverted, conflicted }: WorkflowRunRevertResult) {
  const restored = `${reverted} ${reverted === 1 ? "change" : "changes"} restored`;
  return conflicted > 0 ? `${restored}, ${conflicted} kept — changed since` : restored;
}

function eventLabel(type: string): string {
  if (type === "manual.apply_to_existing") return "Manual run";
  return humanize(type);
}

export function WorkflowRunsPage() {
  const { id } = useParams<{ id: string }>();
  const qc = useQueryClient();
  const confirm = useConfirm();
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);

  const { data: workflow } = useQuery({ ...queries.workflow(id!), enabled: !!id });
  const { data, isLoading, isError, refetch } = useQuery(
    queries.workflowRunGroups({ workflowId: id, status: status || undefined, page })
  );

  const revertRun = useMutation({
    mutationFn: (runId: string) => mutations.revertWorkflowRun(runId),
    onSuccess: (result) => {
      toast.success(revertSummary(result));
      invalidate(qc, keys.workflowRuns);
    },
  });

  const revertAllRuns = useMutation({
    mutationFn: () => mutations.revertWorkflowRuns(id!),
    onSuccess: () => {
      toast.success("Revert queued — runs will be restored in the background");
      invalidate(qc, keys.workflowRuns);
    },
  });

  const onRevert = async (runId: string) => {
    if (await confirm({ title: "Revert this run?", description: REVERT_RUN_DESCRIPTION, confirmLabel: "Revert" })) {
      revertRun.mutate(runId);
    }
  };

  const onRevertAll = async () => {
    if (await confirm({
      title: "Revert all runs of this workflow?",
      description: REVERT_ALL_DESCRIPTION,
      confirmLabel: "Revert",
    })) {
      revertAllRuns.mutate();
    }
  };

  const groups = data?.groups ?? [];
  const total = data?.meta.total ?? 0;
  const perPage = data?.meta.per_page ?? 30;
  const totalPages = Math.max(1, Math.ceil(total / perPage));
  const anyRevertible = groups.some((g) => g.count > g.reverted);

  return (
    <div className="flex h-full flex-col">
      <PageHeader
        title="Runs"
        subtitle={workflow?.name}
        back={{ to: `/workflows/${id}` }}
        actions={!!id && anyRevertible ? [ {
          label: "Revert all runs",
          icon: Undo2,
          destructive: true,
          disabled: revertAllRuns.isPending,
          onSelect: onRevertAll,
        } ] : []}
      >
        <Select
          aria-label="Filter by status"
          value={status}
          onChange={(e) => { setStatus(e.target.value); setPage(1); }}
          wrapperClassName="w-40"
        >
          <option value="">All statuses</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
          ))}
        </Select>
      </PageHeader>

      <div className="flex-1 overflow-y-auto p-6">
        {isError && <ErrorState title="Failed to load runs" onRetry={refetch} />}

        {isLoading && (
          <div className="space-y-2">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="h-12 rounded-xl" />
            ))}
          </div>
        )}

        {!isLoading && !isError && groups.length === 0 && (
          <EmptyState
            title={status ? "No runs match the current filters." : "No runs yet."}
            className="py-24"
          />
        )}

        {!isLoading && !isError && groups.length > 0 && (
          <div className="mx-auto max-w-4xl space-y-2">
            {groups.map((group) =>
              group.count === 1 && group.run ? (
                <RunRow key={group.trace_id} run={group.run} reverting={revertRun.isPending} onRevert={onRevert} />
              ) : (
                <GroupRow
                  key={group.trace_id}
                  group={group}
                  status={status || undefined}
                  reverting={revertRun.isPending}
                  onRevert={onRevert}
                />
              )
            )}

            <Pagination
              variant="simple"
              className="pt-3"
              page={page}
              totalPages={totalPages}
              summary={`${total} groups`}
              onPageChange={setPage}
            />
          </div>
        )}
      </div>
    </div>
  );
}

// ── Group row ─────────────────────────────────────────────────────────────────

const STATUS_ORDER: WorkflowRunStatus[] = ["completed", "failed", "running", "waiting", "pending", "cancelled"];

function GroupRow({ group, status, reverting, onRevert }: {
  group: WorkflowRunGroup;
  status?: string;
  reverting: boolean;
  onRevert: (runId: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);

  const statusParts = STATUS_ORDER.filter((s) => (group.statuses[s] ?? 0) > 0);

  return (
    <div className="rounded-xl border bg-card">
      <button
        onClick={() => setExpanded((e) => !e)}
        aria-expanded={expanded}
        className="flex w-full items-center gap-3 rounded-xl px-4 py-3 text-left hover:bg-accent/50 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        {expanded ? <ChevronDown size={14} className="shrink-0 text-muted-foreground" /> : <ChevronRight size={14} className="shrink-0 text-muted-foreground" />}
        <Layers size={14} className="shrink-0 text-muted-foreground" />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm">
            {group.count} runs · {eventLabel(group.event_type)}
          </span>
          <span className="block truncate text-xs text-muted-foreground">
            {statusParts.map((s, i) => (
              <span key={s}>
                {i > 0 && ", "}
                <span className={cn(s === "failed" && "text-destructive")}>
                  {group.statuses[s]} {s}
                </span>
              </span>
            ))}
            {group.reverted > 0 && <span> · {group.reverted} reverted</span>}
          </span>
        </span>
        <span
          className="shrink-0 text-xs text-muted-foreground"
          title={`${new Date(group.first_at).toLocaleString()} → ${new Date(group.last_at).toLocaleString()}`}
        >
          {formatDistanceToNow(new Date(group.last_at), { addSuffix: true })}
        </span>
      </button>

      {expanded && <GroupRuns group={group} status={status} reverting={reverting} onRevert={onRevert} />}
    </div>
  );
}

function GroupRuns({ group, status, reverting, onRevert }: {
  group: WorkflowRunGroup;
  status?: string;
  reverting: boolean;
  onRevert: (runId: string) => void;
}) {
  const [pageCount, setPageCount] = useState(1);

  return (
    <div className="space-y-2 border-t px-4 py-3 pl-8">
      {Array.from({ length: pageCount }, (_, i) => (
        <GroupRunsPage
          key={i + 1}
          workflowId={group.workflow_id}
          traceId={group.trace_id}
          status={status}
          page={i + 1}
          reverting={reverting}
          onRevert={onRevert}
        />
      ))}
      {group.count > pageCount * GROUP_RUNS_PER_PAGE && (
        <Button
          variant="outline"
          size="sm"
          onClick={() => setPageCount((c) => c + 1)}
          className="w-full text-muted-foreground hover:text-foreground"
        >
          Load more
        </Button>
      )}
    </div>
  );
}

function GroupRunsPage({ workflowId, traceId, status, page, reverting, onRevert }: {
  workflowId: string;
  traceId: string;
  status?: string;
  page: number;
  reverting: boolean;
  onRevert: (runId: string) => void;
}) {
  const { data, isLoading, isError } = useQuery(
    queries.workflowRuns({ workflowId, traceId, status, page })
  );

  if (isLoading) return <Skeleton className="h-10 rounded-lg" />;
  if (isError || !data) return <div className="py-1 text-xs text-destructive">Failed to load runs</div>;

  return (
    <>
      {data.runs.map((run) => (
        <RunRow key={run.id} run={run} reverting={reverting} onRevert={onRevert} />
      ))}
    </>
  );
}

// ── Run row ───────────────────────────────────────────────────────────────────

function RunRow({ run, reverting, onRevert }: { run: WorkflowRun; reverting: boolean; onRevert: (runId: string) => void }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="rounded-xl border bg-card">
      <div className="flex w-full items-center gap-3 px-4 py-3">
        <button
          onClick={() => setExpanded((e) => !e)}
          aria-expanded={expanded}
          className="flex min-w-0 flex-1 items-center gap-3 rounded text-left hover:text-primary transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          {expanded ? <ChevronDown size={14} className="shrink-0 text-muted-foreground" /> : <ChevronRight size={14} className="shrink-0 text-muted-foreground" />}
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm">{eventLabel(run.event_type)}</span>
            {run.subject_type && (
              <span className="block truncate text-xs text-muted-foreground">
                {run.subject_type} {run.subject_id}
              </span>
            )}
          </span>
        </button>
        {run.reverted_at && (
          <Badge variant="outline" title={`Reverted ${new Date(run.reverted_at).toLocaleString()}`}>
            reverted
          </Badge>
        )}
        <RunStatusBadge status={run.status} />
        <span className="shrink-0 text-xs text-muted-foreground">
          {formatDistanceToNow(new Date(run.created_at), { addSuffix: true })}
        </span>
        {run.revertible && (
          <Button
            variant="outline"
            size="xs"
            aria-label={`Revert run ${run.id}`}
            disabled={reverting}
            onClick={() => onRevert(run.id)}
            className="shrink-0 gap-1 text-muted-foreground hover:text-foreground"
          >
            <Undo2 size={12} />
            Revert
          </Button>
        )}
      </div>

      {expanded && <RunDetail runId={run.id} />}
    </div>
  );
}

function RunDetail({ runId }: { runId: string }) {
  const { data: run, isLoading, isError } = useQuery(queries.workflowRun(runId));

  if (isLoading) {
    return (
      <div className="border-t px-4 py-3">
        <Skeleton className="h-8 rounded-lg" />
      </div>
    );
  }
  if (isError || !run) return <div className="border-t px-4 py-3 text-xs text-destructive">Failed to load run detail</div>;

  return (
    <div className="space-y-3 border-t px-4 py-3">
      {run.error && (
        <p className="rounded-lg bg-destructive/10 px-3 py-2 text-xs text-destructive">{run.error}</p>
      )}

      {run.steps.length === 0 && (
        <p className="text-xs text-muted-foreground">No step executions recorded.</p>
      )}

      {run.steps.map((step) => (
        <div key={step.id} className="rounded-lg border px-3 py-2">
          <div className="flex items-center gap-2 text-xs">
            <span className="font-medium">{step.step_kind ?? "step"}</span>
            <RunStatusBadge status={step.status} />
            {step.resume_at && (
              <span className="text-muted-foreground">resumes {formatDistanceToNow(new Date(step.resume_at), { addSuffix: true })}</span>
            )}
            <span className="ml-auto text-muted-foreground">
              {formatDistanceToNow(new Date(step.created_at), { addSuffix: true })}
            </span>
          </div>
          {step.output && Object.keys(step.output).length > 0 && (
            <pre className="mt-2 overflow-x-auto rounded bg-muted px-2 py-1.5 text-caption leading-relaxed text-muted-foreground">
              {JSON.stringify(step.output, null, 2)}
            </pre>
          )}
        </div>
      ))}
    </div>
  );
}
