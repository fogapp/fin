/** Shared plumbing for the chart primitives. */
import { formatDate, formatMonthLabel } from "@/lib/utils";
import type { ChartTheme } from "./theme";

export interface SeriesDef {
  /** Data key in each row. Palette slot = position in the series array. */
  key: string;
  /** Display name (legend/tooltip); defaults to the key. */
  label?: string;
  /** Explicit color — use when a page shares one entity→color assignment
   *  (see assignSeriesColors) between a chart and other panels. */
  color?: string;
}

/** What click handlers receive: the x value plus the full data row. */
export interface ChartDatum {
  x: string;
  row: Record<string, unknown>;
}

export type ChartRow = Record<string, unknown>;

/** Tooltip header: months → "Mar 2026", ISO dates → "Mar 4, 2026". */
export function defaultTooltipLabel(s: string): string {
  if (/^\d{4}-\d{2}$/.test(s)) return `${formatMonthLabel(s)} ${s.slice(0, 4)}`;
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return formatDate(s);
  return s;
}

/** "2026-03" → "Mar"; January shows the year; ISO dates show "MM-DD". */
export function defaultXTickFormat(v: unknown): string {
  const s = String(v);
  if (/^\d{4}-\d{2}$/.test(s)) return s.endsWith("-01") ? s.slice(0, 4) : formatMonthLabel(s);
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s.slice(5);
  return s;
}

export function defaultYFormat(v: number): string {
  const abs = Math.abs(v);
  if (abs >= 1000) return `$${(v / 1000).toFixed(0)}k`;
  return `$${v}`;
}

/** X values where the year changes vs. the previous point (reference lines). */
export function yearBoundaries(data: ChartRow[], xKey: string): string[] {
  const out: string[] = [];
  for (let i = 1; i < data.length; i++) {
    const prev = String(data[i - 1][xKey]).slice(0, 4);
    const cur = String(data[i][xKey]).slice(0, 4);
    if (/^\d{4}$/.test(cur) && prev !== cur) out.push(String(data[i][xKey]));
  }
  return out;
}

export function axisTick(theme: ChartTheme): { fontSize: number; fill: string } {
  return { fontSize: 10, fill: theme.muted };
}

/** Baseline props for a category (x) axis: themed ticks, no tick lines, themed
 * axis line. Shared by the chart primitives and any hand-built recharts
 * composition (NetWorth), so a theme or tick change lands everywhere at once. */
export function categoryAxisProps(theme: ChartTheme) {
  return {
    tick: axisTick(theme),
    tickLine: false,
    axisLine: { stroke: theme.axis },
  } as const;
}

/** Baseline props for a value (y) axis: themed ticks, no tick or axis lines. */
export function valueAxisProps(theme: ChartTheme) {
  return {
    tick: axisTick(theme),
    tickLine: false,
    axisLine: false,
  } as const;
}

/**
 * Legend props — icon carries the series color; the text wears normal ink,
 * never the series color.
 *
 * `matchSeriesOrder` turns off recharts' default alphabetical sort. Set it
 * wherever series order is itself information the reader has to follow —
 * a stack's bottom-to-top order — so scanning the legend and scanning the
 * chart walk the same list.
 */
export function legendProps(theme: ChartTheme, { matchSeriesOrder = false } = {}) {
  return {
    iconType: "plainline" as const,
    iconSize: 12,
    wrapperStyle: { fontSize: 10 },
    itemSorter: matchSeriesOrder ? null : ("value" as const),
    formatter: (value: string) => <span style={{ color: theme.muted }}>{value}</span>,
  };
}

export const MAX_SLOTS = 8;

/**
 * Enforce the fold rule: at most 8 series get palette slots; the rest are
 * summed into a single "Other" series (neutral gray), never a cycled hue.
 */
export function foldSeries(series: SeriesDef[], data: ChartRow[]): { series: SeriesDef[]; data: ChartRow[]; folded: boolean } {
  if (series.length <= MAX_SLOTS) return { series, data, folded: false };
  const kept = series.slice(0, MAX_SLOTS);
  const foldedKeys = series.slice(MAX_SLOTS).map((s) => s.key);
  const foldedData = data.map((row) => {
    const other = foldedKeys.reduce((sum, k) => sum + (typeof row[k] === "number" ? (row[k] as number) : 0), 0);
    return { ...row, __other: other };
  });
  return { series: [...kept, { key: "__other", label: "Other" }], data: foldedData, folded: true };
}

/** Color for slot `i`: an explicit series color wins; the fold slot ("Other")
 *  and anything past the 8 palette slots get the neutral gray. */
export function slotColor(theme: ChartTheme, series: SeriesDef[], i: number): string {
  const explicit = series[i]?.color;
  if (explicit) return explicit;
  if (series[i]?.key === "__other" || i >= MAX_SLOTS) return theme.neutral;
  return theme.series[i];
}

export type CurveMode = "auto" | "monotone" | "linear";

/**
 * Curve honesty: smoothing draws values between data points, so it is only
 * legitimate when the points are dense enough that the curve cannot deviate
 * meaningfully from the data (daily series). Sparse aggregates (monthly
 * totals) get straight segments — the line is a connector between discrete
 * values, and a smooth arc through 8 monthly points invents a shape the
 * data never had.
 */
export const DENSE_SERIES_THRESHOLD = 45;

export function curveFor(pointCount: number): "monotone" | "linear" {
  return pointCount >= DENSE_SERIES_THRESHOLD ? "monotone" : "linear";
}
