import { cn } from "@/lib/utils";
import { budgetFillClass, isPacingOverrun } from "./budgetFill";

/**
 * Bullet-style budget meter. The track represents 125% of the budget and the
 * budget threshold is a fixed line at 80% of the track — constant across every
 * row, so thresholds align vertically and over/under scans at a glance. The
 * neutral grey fill crosses the line when overspent (clamped at 125%), turning
 * amber when approaching budget (≥90%) — or, in the current month, when spend
 * is pacing to exceed it (see budgetFill.ts) — and red once it's exceeded. An
 * optional fainter tick marks how far through the month we are, on the same
 * scale.
 */

// % of budget the full track represents; the budget line lands at 100/125 = 80%.
const TRACK_MAX = 125;
const LINE_LEFT = (100 / TRACK_MAX) * 100;

export function BudgetProgress({
  percentUsed,
  paceElapsed,
  className,
}: {
  percentUsed: number;
  /** 0–100 position of the pace tick; omit to hide it (non-current months). */
  paceElapsed?: number | null;
  className?: string;
}) {
  const width = (Math.min(Math.max(percentUsed, 0), TRACK_MAX) / TRACK_MAX) * 100;
  const fill = budgetFillClass(percentUsed, paceElapsed);
  const pacing = isPacingOverrun(percentUsed, paceElapsed);

  return (
    <div
      className={cn("relative h-2 w-full", className)}
      title={`${Math.round(percentUsed)}% of budget used${pacing ? " — on pace to exceed this budget" : ""}`}
    >
      <div className="h-full w-full overflow-hidden rounded-full bg-muted">
        <div className={cn("h-full rounded-full transition-[width]", fill)} style={{ width: `${width}%` }} />
      </div>
      {/* Budget threshold line */}
      <span
        className="absolute top-1/2 h-3.5 w-0.5 -translate-y-1/2 rounded-full bg-foreground/60"
        style={{ left: `calc(${LINE_LEFT}% - 1px)` }}
      />
      {paceElapsed != null && (
        <span
          className="absolute top-1/2 h-2.5 w-0.5 -translate-y-1/2 rounded-full bg-foreground/25"
          style={{ left: `calc(${(Math.min(Math.max(paceElapsed, 0), 100) / 100) * LINE_LEFT}% - 1px)` }}
          title={`${Math.round(paceElapsed)}% through the month`}
        />
      )}
    </div>
  );
}
