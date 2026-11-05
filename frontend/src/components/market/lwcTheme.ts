/**
 * Bridges the app's semantic CSS tokens into concrete colors for
 * lightweight-charts (a canvas renderer — it needs literal color strings,
 * not CSS classes). Colors are read from the live computed style of the
 * root element, so every one of the 19 themes — and future ones — feeds the
 * chart without a hardcoded palette here. Categorical series colors come
 * from the sanctioned chart palette (charts/theme.ts).
 */
import { useMemo, useSyncExternalStore } from "react";
import { CANVAS_TOKEN_FALLBACKS as FALLBACK } from "@/components/charts/theme";

export interface LwcTheme {
  /** data-theme id ("" for light) — stable key for memoizing chart options. */
  themeId: string;
  text: string;
  muted: string;
  grid: string;
  border: string;
  up: string;
  down: string;
  primary: string;
}

function readVar(style: CSSStyleDeclaration, name: string, fallback: string): string {
  const value = style.getPropertyValue(name).trim();
  return value || fallback;
}

export function readLwcTheme(): LwcTheme {
  if (typeof document === "undefined") {
    return { themeId: "", ...FALLBACK };
  }
  const style = getComputedStyle(document.documentElement);
  return {
    themeId: document.documentElement.getAttribute("data-theme") ?? "",
    text:    readVar(style, "--color-foreground", FALLBACK.text),
    muted:   readVar(style, "--color-muted-foreground", FALLBACK.muted),
    grid:    readVar(style, "--color-border", FALLBACK.grid),
    border:  readVar(style, "--color-border", FALLBACK.border),
    up:      readVar(style, "--color-positive", FALLBACK.up),
    down:    readVar(style, "--color-negative", FALLBACK.down),
    primary: readVar(style, "--color-primary", FALLBACK.primary),
  };
}

function subscribe(onChange: () => void): () => void {
  if (typeof MutationObserver === "undefined") return () => {};
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  return () => observer.disconnect();
}

function getThemeId(): string {
  if (typeof document === "undefined") return "";
  return document.documentElement.getAttribute("data-theme") ?? "";
}

/**
 * Returns the current token colors, re-read whenever data-theme changes.
 * Memoized on the theme id so the object is referentially stable — chart
 * effects can depend on it without re-running every render.
 */
export function useLwcTheme(): LwcTheme {
  const themeId = useSyncExternalStore(subscribe, getThemeId, () => "");
  // eslint-disable-next-line react-hooks/exhaustive-deps -- themeId is the trigger: readLwcTheme re-reads the CSS vars that changed with it
  return useMemo(() => readLwcTheme(), [themeId]);
}
