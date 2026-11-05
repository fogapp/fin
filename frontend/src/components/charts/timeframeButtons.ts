/**
 * The user-configurable timeframe row: one ordered list of button configs
 * shared by every page with a timeframe control, plus which button each page
 * opens on. Persisted in preferences (see hooks/useTimeframeButtons.ts) and
 * resolved against today into TimeframeOptions for useTimeframe.
 */
import {
  builtinOption, isBuiltinTimeframe, iso,
  type BuiltinTimeframe, type TimeframeOption,
} from "./timeframe";
import { formatDate } from "@/lib/utils";

export type RollingUnit = "days" | "weeks" | "months" | "years";

export type TimeframeButtonConfig =
  | { type: "builtin"; key: BuiltinTimeframe }
  /** The last N units, ending today. */
  | { type: "rolling"; id: string; label: string; amount: number; unit: RollingUnit }
  /** An explicit, unchanging from/to window. */
  | { type: "fixed"; id: string; label: string; from: string; to: string };

/** Every page with a timeframe control, and the button each opens on
 *  until the user picks otherwise. */
export const TIMEFRAME_PAGES = [
  { id: "cashflow",    label: "Cashflow",    defaultKey: "1y" },
  { id: "net_worth",   label: "Net Worth",   defaultKey: "1y" },
  { id: "investments", label: "Investments", defaultKey: "all" },
  { id: "categories",  label: "Categories",  defaultKey: "1y" },
  { id: "tags",        label: "Tags",        defaultKey: "1y" },
  { id: "stats",       label: "Stats",       defaultKey: "1y" },
] as const;

export type TimeframePage = typeof TIMEFRAME_PAGES[number]["id"];

export interface TimeframeSettings {
  buttons: TimeframeButtonConfig[];
  /** Key of the button each page opens on. Missing pages use their
   *  TIMEFRAME_PAGES default. */
  defaults: Partial<Record<TimeframePage, string>>;
}

export const DEFAULT_TIMEFRAME_BUTTONS: TimeframeButtonConfig[] =
  (["mtd", "last_month", "3m", "6m", "1y", "ytd", "all"] as const).map((key) => ({ type: "builtin", key }));

export const DEFAULT_TIMEFRAME_SETTINGS: TimeframeSettings = { buttons: DEFAULT_TIMEFRAME_BUTTONS, defaults: {} };

export const ROLLING_UNITS: { value: RollingUnit; label: string; short: string }[] = [
  { value: "days",   label: "Days",   short: "D" },
  { value: "weeks",  label: "Weeks",  short: "W" },
  { value: "months", label: "Months", short: "M" },
  { value: "years",  label: "Years",  short: "Y" },
];

export const MAX_ROLLING_AMOUNT = 120;
export const MAX_LABEL_LENGTH = 12;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function parseIso(s: string): Date {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function buttonKey(b: TimeframeButtonConfig): string {
  return b.type === "builtin" ? b.key : b.id;
}

export function newButtonId(): string {
  return `c_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

/** Same month arithmetic as the 3M/6M/1Y presets, so "12 months" == 1Y. */
export function rollingRange(amount: number, unit: RollingUnit, today: Date = new Date()): { from: string; to: string } {
  const y = today.getFullYear(), m = today.getMonth(), d = today.getDate();
  const from = {
    days:   new Date(y, m, d - amount),
    weeks:  new Date(y, m, d - amount * 7),
    months: new Date(y, m - amount, d),
    years:  new Date(y - amount, m, d),
  }[unit];
  return { from: iso(from), to: iso(today) };
}

export function rollingDescription(amount: number, unit: RollingUnit): string {
  const noun = amount === 1 ? unit.slice(0, -1) : unit;
  return `Last ${amount} ${noun}`;
}

export function suggestRollingLabel(amount: number, unit: RollingUnit): string {
  return `${amount}${ROLLING_UNITS.find((u) => u.value === unit)!.short}`;
}

export function fixedDescription(from: string, to: string): string {
  return `${formatDate(from)} – ${formatDate(to)}`;
}

/** A whole calendar year labels as the year; anything else as M/D–M/D/YY. */
export function suggestFixedLabel(from: string, to: string): string {
  if (from.slice(0, 4) === to.slice(0, 4) && from.endsWith("-01-01") && to.endsWith("-12-31")) {
    return from.slice(0, 4);
  }
  const f = parseIso(from), t = parseIso(to);
  const md = (d: Date) => `${d.getMonth() + 1}/${d.getDate()}`;
  return `${md(f)}–${md(t)}/${String(t.getFullYear()).slice(2)}`;
}

export function resolveButton(b: TimeframeButtonConfig, today: Date = new Date()): TimeframeOption {
  switch (b.type) {
    case "builtin":
      return builtinOption(b.key, today);
    case "rolling":
      return { key: b.id, label: b.label, description: rollingDescription(b.amount, b.unit), ...rollingRange(b.amount, b.unit, today) };
    case "fixed":
      return { key: b.id, label: b.label, description: fixedDescription(b.from, b.to), from: b.from, to: b.to };
  }
}

/** One stored button, or null when it's malformed (hand-edited prefs, an
 *  older schema) — bad entries drop out rather than breaking the row. */
function parseButton(raw: unknown): TimeframeButtonConfig | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (r.type === "builtin") return isBuiltinTimeframe(r.key) ? { type: "builtin", key: r.key } : null;
  if (typeof r.id !== "string" || typeof r.label !== "string" || !r.label.trim()) return null;
  const label = r.label.trim().slice(0, MAX_LABEL_LENGTH);
  if (r.type === "rolling") {
    const amount = Number(r.amount);
    if (!Number.isInteger(amount) || amount < 1 || amount > MAX_ROLLING_AMOUNT) return null;
    if (!ROLLING_UNITS.some((u) => u.value === r.unit)) return null;
    return { type: "rolling", id: r.id, label, amount, unit: r.unit as RollingUnit };
  }
  if (r.type === "fixed") {
    if (typeof r.from !== "string" || typeof r.to !== "string") return null;
    if (!ISO_DATE.test(r.from) || !ISO_DATE.test(r.to) || r.from > r.to) return null;
    return { type: "fixed", id: r.id, label, from: r.from, to: r.to };
  }
  return null;
}

/** Stored settings → usable ones: invalid and duplicate buttons are
 *  dropped, an empty row falls back to the default buttons, and per-page
 *  defaults are kept only when they name a page and a string key (whether
 *  that key is still offered is resolved per page by pageDefaultKey). */
export function parseTimeframeSettings(raw: unknown): { settings: TimeframeSettings; isCustomized: boolean } {
  if (typeof raw !== "object" || raw === null) return { settings: DEFAULT_TIMEFRAME_SETTINGS, isCustomized: false };
  const r = raw as Record<string, unknown>;
  const seen = new Set<string>();
  const parsed = (Array.isArray(r.buttons) ? r.buttons : [])
    .map(parseButton)
    .filter((b): b is TimeframeButtonConfig => {
      if (!b || seen.has(buttonKey(b))) return false;
      seen.add(buttonKey(b));
      return true;
    });
  const rawDefaults = typeof r.defaults === "object" && r.defaults !== null ? r.defaults as Record<string, unknown> : {};
  const defaults: TimeframeSettings["defaults"] = {};
  for (const page of TIMEFRAME_PAGES) {
    const key = rawDefaults[page.id];
    if (typeof key === "string") defaults[page.id] = key;
  }
  const buttons = parsed.length > 0 ? parsed : DEFAULT_TIMEFRAME_BUTTONS;
  const isCustomized = parsed.length > 0 || Object.keys(defaults).length > 0;
  return { settings: { buttons, defaults }, isCustomized };
}

/** The button a page opens on: the user's pick, else the page's built-in
 *  default, else the first button — whichever the row actually offers. */
export function pageDefaultKey(settings: TimeframeSettings, page: TimeframePage): string {
  const keys = settings.buttons.map(buttonKey);
  const builtIn = TIMEFRAME_PAGES.find((p) => p.id === page)!.defaultKey;
  const chosen = settings.defaults[page];
  if (chosen && keys.includes(chosen)) return chosen;
  return keys.includes(builtIn) ? builtIn : keys[0];
}
