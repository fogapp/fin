import { useState } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { formatDistanceToNow } from "date-fns";
import { ChevronDown, ChevronRight } from "lucide-react";
import { queries } from "@/api/queries";
import { Badge } from "@/components/ui/badge";
import { SkeletonList } from "@/components/ui/skeleton";
import { RunStatusBadge } from "@/pages/workflows/WorkflowsIndex";
import { cn } from "@/lib/utils";
import { sourceLabel, formatDuration } from "./format";
import type { ActivityEntry, ActivityGroup, ActivitySeverity } from "@/api/types";
import { isSevere } from "@/lib/severity";

// ── Shared activity primitives ────────────────────────────────────────────────

const SEVERITY_DOT: Record<ActivitySeverity, string> = {
  info: "bg-muted-foreground/40",
  warning: "bg-warning",
  error: "bg-negative",
  critical: "bg-negative",
};

export function SeverityDot({ severity }: { severity: ActivitySeverity }) {
  return (
    <span
      title={severity}
      className={cn("h-2 w-2 shrink-0 rounded-full", SEVERITY_DOT[severity] ?? SEVERITY_DOT.info)}
    />
  );
}

// ── Activity row ──────────────────────────────────────────────────────────────

/** One timeline entry. Expands to the trace episode when the entry carries a
 *  trace_id, or to the raw payload JSON when it doesn't. */
export function ActivityRow({ entry }: { entry: ActivityEntry }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="rounded-xl border bg-card">
      <button
        onClick={() => setExpanded((e) => !e)}
        aria-expanded={expanded}
        className="flex w-full items-center gap-3 rounded-xl px-4 py-2.5 text-left hover:bg-accent/50 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        {expanded
          ? <ChevronDown size={14} className="shrink-0 text-muted-foreground" />
          : <ChevronRight size={14} className="shrink-0 text-muted-foreground" />}
        <SeverityDot severity={entry.severity} />
        <Badge variant="outline" className="shrink-0">{sourceLabel(entry.source)}</Badge>
        <span className="min-w-0 flex-1 truncate text-sm">{entry.summary}</span>
        {entry.duration_ms != null && (
          <span className="shrink-0 text-xs tabular-nums text-muted-foreground">{formatDuration(entry.duration_ms)}</span>
        )}
        <span className="shrink-0 text-xs text-muted-foreground">
          {formatDistanceToNow(new Date(entry.occurred_at), { addSuffix: true })}
        </span>
      </button>

      {expanded && (
        entry.trace_id
          ? <TracePanel traceId={entry.trace_id} />
          : <PayloadPanel payload={entry.payload} />
      )}
    </div>
  );
}

// ── Activity group row ────────────────────────────────────────────────────────

const SEVERITY_RANK: ActivitySeverity[] = ["error", "warning", "info"];

function worstSeverity(group: ActivityGroup): ActivitySeverity {
  return SEVERITY_RANK.find((s) => (group.severities[s] ?? 0) > 0) ?? group.lead.severity;
}

function groupSourcesLabel(sources: string[]): string {
  if (sources.length > 2) return `${sources.length} sources`;
  return sources.map(sourceLabel).join(" · ");
}

/** One causal episode with several entries. Shows the lead (worst, latest)
 *  entry's summary and expands to the episode's trace. */
export function ActivityGroupRow({ group }: { group: ActivityGroup }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="rounded-xl border bg-card">
      <button
        onClick={() => setExpanded((e) => !e)}
        aria-expanded={expanded}
        className="flex w-full items-center gap-3 rounded-xl px-4 py-2.5 text-left hover:bg-accent/50 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        {expanded
          ? <ChevronDown size={14} className="shrink-0 text-muted-foreground" />
          : <ChevronRight size={14} className="shrink-0 text-muted-foreground" />}
        <SeverityDot severity={worstSeverity(group)} />
        <Badge variant="outline" className="shrink-0">{groupSourcesLabel(group.sources)}</Badge>
        <span className="min-w-0 flex-1 truncate text-sm">{group.lead.summary}</span>
        <span className="shrink-0 rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
          {group.count} events
        </span>
        <span
          className="shrink-0 text-xs text-muted-foreground"
          title={`${new Date(group.first_at).toLocaleString()} → ${new Date(group.last_at).toLocaleString()}`}
        >
          {formatDistanceToNow(new Date(group.last_at), { addSuffix: true })}
        </span>
      </button>

      {expanded && (
        group.trace_id
          ? <TracePanel traceId={group.trace_id} />
          : <PayloadPanel payload={group.lead.payload} />
      )}
    </div>
  );
}

function PayloadPanel({ payload }: { payload: Record<string, unknown> | null }) {
  return (
    <div className="border-t px-4 py-3">
      {payload && Object.keys(payload).length > 0 ? (
        <pre className="overflow-x-auto rounded bg-muted px-2 py-1.5 text-caption leading-relaxed text-muted-foreground">
          {JSON.stringify(payload, null, 2)}
        </pre>
      ) : (
        <p className="text-xs text-muted-foreground">No payload recorded.</p>
      )}
    </div>
  );
}

// ── Trace panel ───────────────────────────────────────────────────────────────

/** The full causal episode behind one entry: its trace's entries oldest-first,
 *  then the workflow runs it fired and the notifications those produced. */
function TracePanel({ traceId }: { traceId: string }) {
  const { data, isLoading, isError } = useQuery(queries.activityTrace(traceId));

  if (isLoading) {
    return (
      <div className="border-t px-4 py-3">
        <SkeletonList rows={3} className="space-y-2" rowClassName="h-3" />
      </div>
    );
  }
  if (isError || !data) return <div className="border-t px-4 py-3 text-xs text-destructive">Failed to load trace</div>;

  return (
    <div className="space-y-4 border-t px-4 py-3">
      <ol className="space-y-2">
        {data.entries.map((e) => (
          <li key={e.id} className="flex items-center gap-2 text-xs">
            <SeverityDot severity={e.severity} />
            <Badge variant="outline" className="shrink-0">{sourceLabel(e.source)}</Badge>
            <span className="min-w-0 flex-1 truncate">{e.summary}</span>
            {e.duration_ms != null && (
              <span className="shrink-0 tabular-nums text-muted-foreground">{formatDuration(e.duration_ms)}</span>
            )}
            <span className="shrink-0 text-muted-foreground">
              {formatDistanceToNow(new Date(e.occurred_at), { addSuffix: true })}
            </span>
          </li>
        ))}
      </ol>

      {data.workflow_runs.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Workflow runs</p>
          {data.workflow_runs.map((run) => (
            <div key={run.id} className="flex items-center gap-2 text-xs">
              <Link to={`/workflows/${run.workflow_id}/runs`} className="truncate text-primary hover:underline">
                {run.workflow_name ?? "Workflow"}
              </Link>
              <RunStatusBadge status={run.status} />
              <span className="ml-auto shrink-0 text-muted-foreground">
                {formatDistanceToNow(new Date(run.created_at), { addSuffix: true })}
              </span>
            </div>
          ))}
        </div>
      )}

      {data.notifications.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Notifications</p>
          {data.notifications.map((n) => (
            <div key={n.id} className="flex items-center gap-2 text-xs">
              <span className="min-w-0 flex-1 truncate">{n.title}</span>
              <Badge variant={isSevere(n.severity) ? "destructive" : "outline"}>{n.severity}</Badge>
              <span className="shrink-0 text-muted-foreground">
                {formatDistanceToNow(new Date(n.created_at), { addSuffix: true })}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
