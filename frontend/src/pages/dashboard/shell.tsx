/**
 * Shared building blocks for dashboard sidebar widgets. Every widget renders
 * inside a WidgetShell (label row, optional drill-through link) and composes
 * the small primitives here so the column reads as one system: quiet labels,
 * tabular numbers, meters for progress, sparklines for trends.
 */
import { Link } from "react-router-dom";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { cn, formatPercent } from "@/lib/utils";

/** Uniform props for every registered widget. `showEmpty` is true once the
 *  user has saved an explicit selection: a hand-picked widget with no data
 *  shows an honest empty state instead of silently vanishing. */
export interface WidgetProps {
  showEmpty: boolean;
}

export function WidgetShell({ title, to, meta, children }: {
  title: string;
  /** Drill-through route — the widget title becomes a link. */
  to?: string;
  /** Small right-aligned annotation on the label row (e.g. a window like "6 mo"). */
  meta?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section aria-label={title}>
      <div className="mb-2 flex items-baseline justify-between gap-2">
        {to ? (
          <Link
            to={to}
            className="text-xs font-medium text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-sm"
          >
            {title}
          </Link>
        ) : (
          <p className="text-xs font-medium text-muted-foreground">{title}</p>
        )}
        {meta != null && <span className="text-xs text-muted-foreground/70">{meta}</span>}
      </div>
      {children}
    </section>
  );
}

/** Card surface for non-chart widget bodies (charts bring their own surface). */
export function WidgetCard({ className, children }: { className?: string; children: React.ReactNode }) {
  return (
    <Card>
      <CardContent className={cn("space-y-2 p-3", className)}>{children}</CardContent>
    </Card>
  );
}

export function StatRow({ label, value, valueClassName, sub }: {
  label: string;
  value: React.ReactNode;
  valueClassName?: string;
  sub?: React.ReactNode;
}) {
  return (
    <div className="flex items-baseline justify-between gap-2 text-sm">
      <span className="truncate text-muted-foreground">{label}</span>
      <span className="flex items-baseline gap-1.5">
        {sub != null && <span className="text-xs text-muted-foreground/70">{sub}</span>}
        <span className={cn("tabular-nums font-medium", valueClassName)}>{value}</span>
      </span>
    </div>
  );
}

/** Signed percent delta, colored by whether "up" is good for this metric. */
export function ChangeBadge({ pct, invert = false }: { pct: number | null | undefined; invert?: boolean }) {
  if (pct == null) return null;
  const good = invert ? pct <= 0 : pct >= 0;
  return (
    <span className={cn("text-xs tabular-nums", good ? "text-positive" : "text-negative")}>
      {formatPercent(pct)}
    </span>
  );
}

/**
 * Thin progress meter with an optional pace marker (a tick at, say, the
 * percent of the month elapsed) so "spent vs planned" reads at a glance.
 */
export function MeterBar({ value, max, markerPct, tone = "primary" }: {
  value: number;
  max: number;
  /** 0–100 position for the pace tick. */
  markerPct?: number;
  tone?: "primary" | "warning" | "negative";
}) {
  const pct = max > 0 ? Math.min(100, Math.max(0, (value / max) * 100)) : 0;
  const fill = { primary: "bg-primary", warning: "bg-warning", negative: "bg-negative" }[tone];
  return (
    <div className="relative h-1.5 w-full overflow-hidden rounded-full bg-muted">
      <div className={cn("h-full rounded-full", fill)} style={{ width: `${pct}%` }} />
      {markerPct != null && markerPct > 0 && markerPct < 100 && (
        <div
          className="absolute top-0 h-full w-0.5 bg-foreground/40"
          style={{ left: `${markerPct}%` }}
          aria-hidden
        />
      )}
    </div>
  );
}

export function WidgetSkeleton({ className }: { className?: string }) {
  return <Skeleton className={cn("h-28 rounded-xl", className)} />;
}

/** Compact per-widget failure state — a failed section never silently hides. */
export function WidgetError({ onRetry }: { onRetry: () => void }) {
  return (
    <WidgetCard className="flex items-center justify-between gap-2 space-y-0">
      <span className="text-xs text-muted-foreground">Couldn’t load.</span>
      <Button variant="outline" size="xs" onClick={onRetry}>Retry</Button>
    </WidgetCard>
  );
}
