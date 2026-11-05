import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Sign tint for money values: gains `text-positive`, losses `text-negative`,
 * zero stays the surrounding text color. The single source of truth — don't
 * re-implement this ternary inline. */
export function moneyColor(value: number): string {
  if (value > 0) return "text-positive";
  if (value < 0) return "text-negative";
  return "";
}

export function formatCurrency(value: number | null | undefined, compact = false): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    notation: compact ? "compact" : "standard",
    maximumFractionDigits: compact ? 1 : 2,
  }).format(value);
}

/** Whole dollars — "$1,250" — for budget amounts and other round figures
 * where cents are noise. */
export function formatDollars(value: number | null | undefined): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(value);
}

/** Compact plain number for counts like volume or shares out — "1.2M", no
 * currency symbol. Omitting `maximumFractionDigits` keeps Intl's compact
 * default (one fraction digit). */
export function formatCompactNumber(value: number | null | undefined, maximumFractionDigits?: number): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits }).format(value);
}

export function formatPercent(value: number | null | undefined): string {
  if (value == null) return "—";
  const sign = value >= 0 ? "+" : "";
  return `${sign}${value.toFixed(1)}%`;
}

/** File sizes in binary units: "285 KB", "1.4 GB". */
export function formatBytes(value: number | null | undefined): string {
  if (value == null) return "—";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = value;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size >= 10 || unit === 0 ? Math.round(size) : size.toFixed(1)} ${units[unit]}`;
}

/** A moment, for things that happen more than once a day: "Sep 30, 9:48 AM". */
export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  return new Date(value).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  // Plain yyyy-mm-dd strings are parsed as UTC midnight by `new Date`, which
  // renders one day early in negative-UTC timezones — parse them as LOCAL dates.
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const date = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(value);
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

/** Formats a "yyyy-mm" or "yyyy-mm-dd" value as an abbreviated month name ("Jan"). */
export function formatMonthLabel(value: unknown): string {
  return new Date(String(value).slice(0, 7) + "-02").toLocaleDateString("en-US", { month: "short" });
}

/** Like fillLastMonths, but the window starts at `from` (an ISO date). When
 *  `from` is omitted (an "All" timeframe) the window starts at the earliest
 *  month present in the data, with a 24-month floor and a 10-year cap. */
export function fillMonthsFrom(data: Record<string, number>, from?: string): { month: string; amount: number }[] {
  const today = new Date();
  let start: Date | null = null;
  if (from) {
    const m = /^(\d{4})-(\d{2})/.exec(from);
    if (m) start = new Date(Number(m[1]), Number(m[2]) - 1, 1);
  } else {
    const earliest = Object.keys(data).map((k) => k.slice(0, 7)).sort()[0];
    if (earliest) start = new Date(Number(earliest.slice(0, 4)), Number(earliest.slice(5, 7)) - 1, 1);
  }
  if (!start) return fillLastMonths(data);
  const n = (today.getFullYear() - start.getFullYear()) * 12 + (today.getMonth() - start.getMonth()) + 1;
  return fillLastMonths(data, Math.min(Math.max(from ? n : Math.max(n, 24), 1), 120));
}

/** Returns the last N calendar months as { month: "yyyy-mm", amount } entries,
 *  filling zeros for any month not present in the source data. */
export function fillLastMonths(data: Record<string, number>, n = 24): { month: string; amount: number }[] {
  const today = new Date();
  // Build a normalised lookup keyed by "yyyy-mm"
  const lookup: Record<string, number> = {};
  for (const [key, val] of Object.entries(data)) {
    lookup[key.slice(0, 7)] = val;
  }
  return Array.from({ length: n }, (_, i) => {
    const d = new Date(today.getFullYear(), today.getMonth() - (n - 1 - i), 1);
    const month = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    return { month, amount: lookup[month] ?? 0 };
  });
}
