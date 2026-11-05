import { useQuery } from "@tanstack/react-query";
import { Link, useNavigate } from "react-router-dom";
import { formatDistanceToNow } from "date-fns";
import { queries } from "@/api/queries";
import { cn } from "@/lib/utils";
import { ErrorState } from "@/components/PageState";
import { Skeleton } from "@/components/ui/skeleton";
import { priceSourceLabel } from "@/lib/marketData";
import { isSevere } from "@/lib/severity";
import { SeverityDot } from "./ActivityRow";
import { filterKeyForSource } from "./filters";
import { sourceLabel, formatDuration } from "./format";
import type { SystemHealthSource, MarketDataProvider } from "@/api/types";

const RETRY_NOTE = "Failed fetches retry automatically with backoff.";

/** Status panel above the timeline. Every number is a plain-language tile that
 *  navigates somewhere useful; when everything is clean it collapses to a
 *  single quiet line. */
export function HealthStrip({ onFilter, onFocusReconciliation }: {
  /** Applies a timeline filter by key (chip keys plus tile-only keys). */
  onFilter: (filterKey: string) => void;
  /** Scrolls to / highlights the reconciliation panel below. */
  onFocusReconciliation: () => void;
}) {
  const navigate = useNavigate();
  const { data, isLoading, isError, refetch } = useQuery(queries.systemHealth());

  if (isError) {
    return (
      <div className="rounded-xl border bg-card">
        <ErrorState title="Failed to load system health" onRetry={() => refetch()} />
      </div>
    );
  }
  if (isLoading || !data) return <Skeleton className="h-24 rounded-xl" />;

  const marketData = data.market_data;
  const healthy =
    data.errors_24h === 0 &&
    data.workflows.failed_7d === 0 &&
    marketData.open_drift_findings === 0 &&
    marketData.stale_held_instruments === 0 &&
    marketData.providers.every((p) => p.failing === 0);

  const lastSyncAt = data.sources.reduce<string | null>(
    (latest, s) => (!latest || new Date(s.occurred_at) > new Date(latest) ? s.occurred_at : latest),
    null
  );

  if (healthy) {
    return (
      <p className="rounded-xl border bg-card px-4 py-3 text-sm text-muted-foreground">
        All systems healthy — syncs, workflows, prices, and reconciliation are clean.
        {lastSyncAt && (
          <span> Last sync {formatDistanceToNow(new Date(lastSyncAt), { addSuffix: true })}.</span>
        )}
      </p>
    );
  }

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
        <StatTile
          label="Errors"
          sub="last 24 hours"
          value={data.errors_24h}
          alert={data.errors_24h > 0}
          title="Show error events in the timeline"
          onClick={() => onFilter("errors")}
        />
        <StatTile
          label="Workflow failures"
          sub="last 7 days"
          value={data.workflows.failed_7d}
          alert={data.workflows.failed_7d > 0}
          title="Show failed workflow events in the timeline"
          onClick={() => onFilter("workflow_failures")}
        />
        <StatTile
          label="Holdings drift"
          sub="ledger vs. custodian mismatches"
          value={marketData.open_drift_findings}
          alert={marketData.open_drift_findings > 0}
          title="Review reconciliation findings below"
          onClick={onFocusReconciliation}
        />
        <StatTile
          label="Stale prices"
          sub="held instruments without a fresh price"
          value={marketData.stale_held_instruments}
          alert={marketData.stale_held_instruments > 0}
          title="Open market data — stale rows carry staleness badges"
          onClick={() => navigate("/market")}
        />
      </div>

      {(data.sources.length > 0 || marketData.providers.length > 0) && (
        <div className="flex gap-2 overflow-x-auto pb-1">
          {data.sources.map((s) => <SourceCard key={s.source} source={s} onFilter={onFilter} />)}
          {marketData.providers.map((p) => <ProviderCard key={p.provider} provider={p} />)}
        </div>
      )}
    </div>
  );
}

function StatTile({ label, sub, value, alert, title, onClick }: {
  label: string;
  sub: string;
  value: number;
  alert: boolean;
  title: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      title={title}
      className={cn(
        "rounded-xl border bg-card px-3 py-2 text-left transition-colors hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        alert && "border-negative/50 bg-negative/5 hover:bg-negative/10",
      )}
    >
      <p className="text-tiny font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={cn("text-base font-semibold tabular-nums", alert && "text-destructive")}>
        {value.toLocaleString()}
      </p>
      <p className="truncate text-tiny text-muted-foreground">{sub}</p>
    </button>
  );
}

function SourceCard({ source: s, onFilter }: { source: SystemHealthSource; onFilter: (filterKey: string) => void }) {
  const filterKey = filterKeyForSource(s.source);
  const relative = formatDistanceToNow(new Date(s.occurred_at), { addSuffix: true });

  const body = (
    <>
      <div className="flex items-center gap-1.5">
        <SeverityDot severity={s.severity} />
        <p className="truncate text-xs font-medium">{sourceLabel(s.source)}</p>
        <span className="ml-auto shrink-0 text-tiny text-muted-foreground">{relative}</span>
      </div>
      <p className="mt-1 truncate text-caption text-muted-foreground">
        {s.summary}
        {s.duration_ms != null && <span className="ml-1 tabular-nums">· {formatDuration(s.duration_ms)}</span>}
      </p>
    </>
  );

  const className = cn(
    "w-48 shrink-0 rounded-xl border bg-card px-3 py-2 text-left",
    isSevere(s.severity) && "border-negative/50 bg-negative/5",
  );
  const tooltip = `${s.summary} — ${relative}`;

  if (!filterKey) {
    return <div className={className} title={tooltip}>{body}</div>;
  }

  return (
    <button
      onClick={() => onFilter(filterKey)}
      title={tooltip}
      className={cn(
        className,
        "transition-colors hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        isSevere(s.severity) && "hover:bg-negative/10",
      )}
    >
      {body}
    </button>
  );
}

function ProviderCard({ provider: p }: { provider: MarketDataProvider }) {
  const failing = p.failing > 0;
  const tooltip = failing
    ? [p.last_error, RETRY_NOTE].filter(Boolean).join(" — ")
    : "All instruments fetching normally. Open market data.";

  return (
    <Link
      to="/market"
      title={tooltip}
      className={cn(
        "w-48 shrink-0 rounded-xl border bg-card px-3 py-2 transition-colors hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        failing && "border-negative/50 bg-negative/5 hover:bg-negative/10",
      )}
    >
      <div className="flex items-center gap-1.5">
        <span className={cn("h-2 w-2 shrink-0 rounded-full", failing ? "bg-negative" : "bg-muted-foreground/40")} />
        <p className="truncate text-xs font-medium">{priceSourceLabel(p.provider)}</p>
      </div>
      {failing ? (
        <p className="mt-1 truncate text-caption font-medium tabular-nums text-destructive">
          {p.failing} of {p.instruments.toLocaleString()} instrument{p.instruments === 1 ? "" : "s"} failing
        </p>
      ) : (
        <p className="mt-1 truncate text-caption text-muted-foreground">healthy</p>
      )}
    </Link>
  );
}
