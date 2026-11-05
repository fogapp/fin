/** Timeframe presets + `{from, to}` mapping (see TimeframeSelector.tsx). */
import { useState } from "react";

/** Every built-in relative period. The app's timeframe row is user-configured
 *  from these plus custom buttons (timeframeButtons.ts); TIMEFRAME_PRESETS is
 *  the fallback row for a bare useTimeframe/TimeframeSelector. */
export type BuiltinTimeframe =
  | "mtd" | "last_month" | "qtd" | "last_quarter"
  | "3m" | "6m" | "1y" | "ytd" | "last_year" | "all";

export type TimeframePreset = BuiltinTimeframe | "custom";

/** One button in a timeframe row, resolved against today. `key` is what
 *  useTimeframe stores; user-defined buttons carry generated keys. */
export interface TimeframeOption {
  key: string;
  label: string;
  /** Long form for subtitles and tooltips ("Last 12 months"). */
  description: string;
  from?: string;
  to?: string;
}

/** A local-time date as "YYYY-MM-DD" (toISOString would give the UTC day). */
export function iso(d: Date = new Date()): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

const MONTH_ABBR = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Built-in catalog. Calendar periods that have ended label themselves with
 *  the period ("Aug", "Q2", "2025") so the button says exactly what it shows. */
export const BUILTIN_TIMEFRAMES: Record<BuiltinTimeframe, {
  label: (today: Date) => string;
  description: string;
}> = {
  mtd:          { label: () => "MTD", description: "Month to date" },
  last_month:   { label: (t) => MONTH_ABBR[(t.getMonth() + 11) % 12], description: "Last complete month" },
  qtd:          { label: () => "QTD", description: "Quarter to date" },
  last_quarter: { label: (t) => `Q${((Math.floor(t.getMonth() / 3) + 3) % 4) + 1}`, description: "Last complete quarter" },
  "3m":         { label: () => "3M", description: "Last 3 months" },
  "6m":         { label: () => "6M", description: "Last 6 months" },
  "1y":         { label: () => "1Y", description: "Last 12 months" },
  ytd:          { label: () => "YTD", description: "Year to date" },
  last_year:    { label: (t) => String(t.getFullYear() - 1), description: "Last calendar year" },
  all:          { label: () => "All", description: "All time" },
};

export const BUILTIN_TIMEFRAME_KEYS = Object.keys(BUILTIN_TIMEFRAMES) as BuiltinTimeframe[];

export function isBuiltinTimeframe(key: unknown): key is BuiltinTimeframe {
  return typeof key === "string" && Object.hasOwn(BUILTIN_TIMEFRAMES, key);
}

/** Presets map to `{from, to}` ISO dates; "all" omits both so the backend
 *  falls back to its default window. "custom" carries no dates of its own —
 *  useTimeframe substitutes the stored custom range. */
export function timeframeRange(preset: TimeframePreset, today: Date = new Date()): { from?: string; to?: string } {
  if (preset === "all" || preset === "custom") return {};
  const y = today.getFullYear();
  const m = today.getMonth();
  const to = iso(today);
  const quarterStart = Math.floor(m / 3) * 3;
  switch (preset) {
    case "mtd":          return { from: iso(new Date(y, m, 1)), to };
    case "last_month":   return { from: iso(new Date(y, m - 1, 1)), to: iso(new Date(y, m, 0)) };
    case "qtd":          return { from: iso(new Date(y, quarterStart, 1)), to };
    case "last_quarter": return { from: iso(new Date(y, quarterStart - 3, 1)), to: iso(new Date(y, quarterStart, 0)) };
    case "3m":           return { from: iso(new Date(y, m - 3, today.getDate())), to };
    case "6m":           return { from: iso(new Date(y, m - 6, today.getDate())), to };
    case "1y":           return { from: iso(new Date(y - 1, m, today.getDate())), to };
    case "ytd":          return { from: `${y}-01-01`, to };
    case "last_year":    return { from: `${y - 1}-01-01`, to: `${y - 1}-12-31` };
  }
}

export function builtinOption(key: BuiltinTimeframe, today: Date = new Date()): TimeframeOption {
  const def = BUILTIN_TIMEFRAMES[key];
  return { key, label: def.label(today), description: def.description, ...timeframeRange(key, today) };
}

/** The default row for pages that don't configure their own. */
export const TIMEFRAME_PRESETS: { key: BuiltinTimeframe; label: string }[] =
  (["3m", "6m", "1y", "ytd", "all"] as const).map((key) => ({ key, label: BUILTIN_TIMEFRAMES[key].label(new Date()) }));

export interface CustomRange {
  from: string;
  to: string;
}

export interface Timeframe {
  /** The active option's key, or "custom". */
  preset: string;
  setPreset: (p: string) => void;
  /** Switch to an explicit from/to window (activates the "custom" preset). */
  setCustom: (range: CustomRange) => void;
  /** The stored custom window, kept even while a preset is active so the
   *  Custom panel re-opens with its last values. */
  customRange: CustomRange | null;
  /** The buttons this timeframe offers, in display order. */
  options: TimeframeOption[];
  /** Long label for the active window ("Last 12 months", "Custom range"). */
  description: string;
  from?: string;
  to?: string;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function readCustom(storageKey?: string): CustomRange | null {
  if (!storageKey) return null;
  try {
    const raw = sessionStorage.getItem(`${storageKey}:custom`);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CustomRange;
    if (ISO_DATE.test(parsed.from) && ISO_DATE.test(parsed.to)) return parsed;
  } catch { /* fall through */ }
  return null;
}

/**
 * Page-scoped timeframe state. `options` defaults to TIMEFRAME_PRESETS; a
 * page with a configurable row passes its resolved options instead, which may
 * arrive after first render (preferences load async). The stored selection is
 * kept as-is and only resolved against `options` at render time, so a
 * selection that isn't offered (yet, or any more) falls back to the default
 * without being overwritten.
 */
export function useTimeframe({ defaultPreset = "1y", storageKey, options }: {
  defaultPreset?: string;
  storageKey?: string;
  options?: TimeframeOption[];
} = {}): Timeframe {
  const [custom, setCustomState] = useState<CustomRange | null>(() => readCustom(storageKey));
  const [selected, setSelected] = useState<string | null>(() =>
    storageKey ? sessionStorage.getItem(storageKey) : null,
  );

  const today = new Date();
  const offered = options ?? TIMEFRAME_PRESETS.map((p) => builtinOption(p.key, today));

  function setPreset(next: string) {
    if (storageKey) sessionStorage.setItem(storageKey, next);
    setSelected(next);
  }

  function setCustom(range: CustomRange) {
    if (storageKey) sessionStorage.setItem(`${storageKey}:custom`, JSON.stringify(range));
    setCustomState(range);
    setPreset("custom");
  }

  if (selected === "custom" && custom) {
    return {
      preset: "custom", setPreset, setCustom, customRange: custom, options: offered,
      description: "Custom range", from: custom.from, to: custom.to,
    };
  }

  const active =
    offered.find((o) => o.key === selected) ??
    offered.find((o) => o.key === defaultPreset) ??
    offered[0] ??
    builtinOption("all", today);
  return {
    preset: active.key, setPreset, setCustom, customRange: custom, options: offered,
    description: active.description, from: active.from, to: active.to,
  };
}
