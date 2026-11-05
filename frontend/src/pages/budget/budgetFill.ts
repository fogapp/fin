/**
 * The one fill-color rule for budget meters: red once exceeded, amber when
 * approaching (≥90%), and — for the current month only — amber when spend is
 * *pacing* to exceed the budget by month end (percentUsed has crossed the
 * share of the month already elapsed), so an overrun warns while there is
 * still time to react. The pace check waits until 10% of the month has
 * elapsed so day-one purchases don't flap the warning.
 */
export function budgetFillClass(percentUsed: number | null, paceElapsed?: number | null): string {
  if (percentUsed == null) return "bg-muted-foreground/60";
  if (percentUsed >= 100) return "bg-negative";
  if (percentUsed >= 90) return "bg-warning";
  if (paceElapsed != null && paceElapsed >= 10 && percentUsed > paceElapsed) return "bg-warning";
  return "bg-muted-foreground/60";
}

/** True when the amber state comes from pacing rather than the ≥90% floor —
 *  lets meters explain themselves ("on pace to exceed"). */
export function isPacingOverrun(percentUsed: number, paceElapsed?: number | null): boolean {
  return percentUsed < 90 && paceElapsed != null && paceElapsed >= 10 && percentUsed > paceElapsed;
}
