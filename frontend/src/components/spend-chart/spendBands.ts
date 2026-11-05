/**
 * Turns the spend-breakdown payload into chart series + rows for the Spending
 * chart's stacked modes. Pure, because the folding rules below are the part
 * that's easy to get subtly wrong.
 */
import type { SeriesDef, ChartRow } from "@/components/charts";
import type { SpendBreakdown, SpendBreakdownData } from "@/api/types";

/** The remainder band (see Api::Render::Cashflow#monthly_breakdown): the
 *  ranked tail plus everything the ranked scope can't see — uncategorized
 *  rows, merchant-less rows. Always neutral gray, never a palette slot. */
export const OTHER_ID = "other";

/** Amounts, or each month normalized to its own 100%. */
export type SpendScale = "amount" | "share";

export interface SpendBands {
  /** Rank order, which is also stacking order (bottom-up); "Other" last. */
  series: SeriesDef[];
  rows: ChartRow[];
}

/** Band names across both variants, minus the "Other" remainder — excluding
 *  outliers can shrink a big spender enough to reshuffle the top-8, and a
 *  color that survives the Common toggle needs the union. */
export function bandNames(data: SpendBreakdownData | undefined, dimension: "category" | "merchant"): { name: string }[] {
  if (!data) return [];
  return [...(data[dimension]?.series ?? []), ...(data[`${dimension}_common`]?.series ?? [])]
    .filter((band) => band.id !== OTHER_ID);
}

/**
 * @param months  x-axis month keys ("YYYY-MM"), supplied by the caller so the
 *                stacked modes span exactly the months the Total line does.
 * @param colors  the page's one entity→color assignment.
 * @param neutral the fallback color — a band that resolves to it has no
 *                palette slot left.
 */
export function buildSpendBands(
  breakdown: SpendBreakdown,
  months: string[],
  colors: Map<string, string>,
  neutral: string,
  scale: SpendScale,
): SpendBands {
  // A band with no slot left merges INTO Other rather than rendering as a
  // second neutral-gray band beside it: a list row can wear the fallback gray
  // because its name sits right there in the row, but two identically-filled
  // bands in one stack are simply unreadable.
  const slotted = breakdown.series.filter(
    (band) => band.id !== OTHER_ID && colors.get(band.name) !== neutral,
  );
  const kept = new Set(slotted.map((band) => band.id));
  const hasOther = slotted.length < breakdown.series.length;

  const series: SeriesDef[] = slotted.map((band) => ({
    key: band.id,
    label: band.name,
    color: colors.get(band.name),
  }));
  if (hasOther) series.push({ key: OTHER_ID, label: "Other", color: neutral });

  // Payload keys are "YYYY-MM-01"; the month axis is "YYYY-MM".
  const byMonth = new Map(Object.entries(breakdown.months).map(([key, values]) => [key.slice(0, 7), values]));

  const rows = months.map((month) => {
    const row: ChartRow = { month };
    let other = 0;
    for (const [id, amount] of Object.entries(byMonth.get(month) ?? {})) {
      // A normalized stack can't represent a negative band, so share mode
      // floors a refund-heavy band at zero. Amount mode keeps the real number:
      // stacked bars render below the baseline honestly.
      const value = scale === "share" ? Math.max(amount, 0) : amount;
      if (kept.has(id)) row[id] = value;
      else other += value;
    }
    if (hasOther) row[OTHER_ID] = Math.round(other * 100) / 100;
    return row;
  });

  return { series, rows };
}
