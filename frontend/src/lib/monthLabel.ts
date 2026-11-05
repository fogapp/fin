// Month labels are memoized at module level: `new Date().toLocaleDateString()`
// per row per render was measurably slow on 250-row table pages.

const MONTH_LABEL_FMT = new Intl.DateTimeFormat("en-US", { month: "long", year: "numeric" });
const cache = new Map<string, string>();

/** "2026-08" → "August 2026", cached. */
export function monthLabel(key: string): string {
  let label = cache.get(key);
  if (label === undefined) {
    const [year, month] = key.split("-");
    label = MONTH_LABEL_FMT.format(new Date(Number(year), Number(month) - 1));
    cache.set(key, label);
  }
  return label;
}
