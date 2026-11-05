import { formatCurrency } from "@/lib/utils";
import type { StatDirection, StatUnit } from "@/api/types";

// The single formatting point for the Stats system: index cards, the detail
// hero, summary ribbons, and chart axes/tooltips all format through here so
// a currency/count/percent stat presents identically everywhere.

/** Full-precision value formatting. Percent is UNSIGNED — the signed
 *  formatPercent from lib/utils is reserved for change deltas. */
export function formatStatValue(
  value: number | null | undefined,
  unit: StatUnit,
  opts?: { compact?: boolean },
): string {
  if (value == null) return "—";
  switch (unit) {
    case "currency":
      return formatCurrency(value, opts?.compact ?? false);
    case "percent":
      return `${value.toFixed(1)}%`;
    case "count":
      return new Intl.NumberFormat("en-US", {
        notation: opts?.compact ? "compact" : "standard",
        maximumFractionDigits: opts?.compact || !Number.isInteger(value) ? 1 : 0,
      }).format(value);
  }
}

/** Compact axis-tick formatter for charts ($1.2K / 1.2K / 12%). */
export function statYFormat(unit: StatUnit): (v: number) => string {
  return (v) => formatStatValue(v, unit, { compact: true });
}

/** Full-precision tooltip formatter for charts. */
export function statTooltipFormat(unit: StatUnit): (v: number) => string {
  return (v) => formatStatValue(v, unit);
}

/** Whether a positive change should render as bad (StatRibbon invertColor). */
export function invertColorFor(direction: StatDirection): boolean {
  return direction === "down_good";
}

/** The only place the frontend hardcodes stat keys: existing subheader
 *  ribbon items that link through to their stat detail pages. Keys must
 *  match the backend Metrics::Registry. */
export const STAT_LINKS = {
  monthlySpend: "/stats/monthly_spend",
  monthlyIncome: "/stats/monthly_income",
  ccTransactionCount: "/stats/cc_transaction_count",
  ccAvgTransaction: "/stats/cc_avg_transaction",
} as const;

const monthKey = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;

/**
 * Month-to-date spend, and its % change against the prior month prorated to
 * the same day of the month (so the 10th compares with a third of last
 * month). `change` is null when there's no prior spend to compare against.
 */
export function mtdVsProratedPrior(
  monthly: { month: string; amount: number }[],
  today: Date = new Date(),
): { mtd: number; change: number | null } {
  const byMonth = Object.fromEntries(monthly.map(({ month, amount }) => [month, amount]));
  const mtd = byMonth[monthKey(today)] ?? 0;
  const prev = byMonth[monthKey(new Date(today.getFullYear(), today.getMonth() - 1, 1))] ?? 0;
  const fraction = today.getDate() / new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
  const proratedPrev = prev * fraction;
  return { mtd, change: proratedPrev > 0 ? ((mtd - proratedPrev) / proratedPrev) * 100 : null };
}
