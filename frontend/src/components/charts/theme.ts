/**
 * Unified chart theme.
 *
 * The palette is a fixed, validated set (CVD-safe adjacency + contrast checked):
 * slots are assigned in THIS order to a chart's ordered series list and are
 * never cycled — a 9th series folds into "Other" (neutral gray). Color follows
 * the entity, never its rank: charts index into the palette by the fixed order
 * of the series list they receive, so filtering series never repaints survivors.
 *
 * Light slots 2/3/7 are below 3:1 contrast on white — every chart that uses
 * them must carry a legend or direct labels (all multi-series charts here do).
 */
import { useSyncExternalStore } from "react";

export const LIGHT_SERIES: readonly string[] = [
  "#2a78d6", "#1baf7a", "#eda100", "#008300", "#4a3aa7", "#e34948", "#e87ba4", "#eb6834",
];

export const DARK_SERIES: readonly string[] = [
  "#3987e5", "#199e70", "#c98500", "#008300", "#9085e9", "#e66767", "#d55181", "#d95926",
];

export type ChartMode = "light" | "dark";

/**
 * Token fallbacks for canvas renderers (lightweight-charts) in environments
 * where CSS custom properties can't be read (SSR, jsdom). Live rendering
 * always reads the real tokens; these only prevent unstyled flashes.
 */
export const CANVAS_TOKEN_FALLBACKS = {
  text:    "#333333",
  muted:   "#898781",
  grid:    "#e1e0d9",
  border:  "#c3c2b7",
  up:      "#22883e",
  down:    "#c22f2f",
  primary: "#2a78d6",
} as const;

export interface ChartTheme {
  mode: ChartMode;
  /** Categorical palette — index by fixed series order, never cycle. */
  series: readonly string[];
  /** Recessive horizontal hairline gridlines. */
  grid: string;
  /** Axis baseline color. */
  axis: string;
  /** Axis tick / muted label ink (both modes). */
  muted: string;
  /** Chart surface — used for the 2px gaps between bar fills. */
  surface: string;
  /** Diverging pair (positive/negative, e.g. net cashflow) + neutral midpoint. */
  positive: string;
  negative: string;
  neutral: string;
}

const THEMES: Record<ChartMode, ChartTheme> = {
  light: {
    mode: "light",
    series: LIGHT_SERIES,
    grid: "#e1e0d9",
    axis: "#c3c2b7",
    muted: "#898781",
    surface: "var(--color-card)",
    positive: "#2a78d6",
    negative: "#e34948",
    neutral: "#898781",
  },
  dark: {
    mode: "dark",
    series: DARK_SERIES,
    grid: "#2c2c2a",
    axis: "#383835",
    muted: "#898781",
    surface: "var(--color-card)",
    positive: "#3987e5",
    negative: "#e66767",
    neutral: "#898781",
  },
};

/** data-theme values that render on a dark chart surface (see useTheme.ts). */
const DARK_THEME_IDS = new Set(["dark", "midnight", "dusk", "slate", "ember"]);

export function chartModeFor(themeId: string | null): ChartMode {
  return themeId && DARK_THEME_IDS.has(themeId) ? "dark" : "light";
}

/**
 * Pick the color for the nth series slot. Slots are NEVER cycled — series
 * beyond the 8th get the neutral "Other" gray (callers should fold instead).
 */
export function seriesColor(theme: ChartTheme, index: number): string {
  return index < theme.series.length ? theme.series[index] : theme.neutral;
}

/**
 * ONE entity→color assignment to share across every panel on a page/section:
 * color follows the entity everywhere, so a chart's series and any adjacent
 * colored list dots for the same entity must resolve through the same map.
 * Slots go by fixed order of first appearance and are never cycled — a 9th+
 * entity gets the neutral gray. Look up with `map.get(name) ?? theme.neutral`
 * so entities that never got a slot (e.g. list rows not in the chart) fall to
 * neutral instead of claiming a new slot.
 */
export function assignSeriesColors(names: readonly string[], theme: ChartTheme): Map<string, string> {
  const map = new Map<string, string>();
  for (const name of names) {
    if (!map.has(name)) map.set(name, seriesColor(theme, map.size));
  }
  return map;
}

/**
 * Dashboard `activity_chart` buckets no longer carry a server-side color —
 * assign palette slots client-side by this fixed bucket order.
 */
export const ACTIVITY_BUCKET_ORDER = ["Buys", "Sells", "Dividends", "Interest", "Fees", "Other"] as const;

export function activityBucketColor(theme: ChartTheme, name: string): string {
  const idx = (ACTIVITY_BUCKET_ORDER as readonly string[]).indexOf(name);
  return idx === -1 ? theme.neutral : seriesColor(theme, idx);
}

// ── Live mode subscription ────────────────────────────────────────────────────
// Watches [data-theme] on the root element so charts recolor when the user
// switches themes, without prop drilling.

function getMode(): ChartMode {
  if (typeof document === "undefined") return "light";
  return chartModeFor(document.documentElement.getAttribute("data-theme"));
}

function subscribe(onChange: () => void): () => void {
  if (typeof MutationObserver === "undefined") return () => {};
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  return () => observer.disconnect();
}

export function useChartTheme(): ChartTheme {
  const mode = useSyncExternalStore(subscribe, getMode, () => "light" as const);
  return THEMES[mode];
}
