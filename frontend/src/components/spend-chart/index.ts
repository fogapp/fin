/**
 * The reusable segmented spend chart — one card for every page that shows
 * spend over time, self-fed from GET /cashflow/spend_breakdown.
 */
export { SpendChartCard } from "./SpendChartCard";
export type { SpendChartScope, SpendTotals } from "./SpendChartCard";
export { useSpendChartControls, SPEND_SERIES_OPTIONS } from "./useSpendChartControls";
export type { SpendChartControls, SpendDimension, SpendSeriesMode } from "./useSpendChartControls";
export { buildSpendBands, bandNames, OTHER_ID } from "./spendBands";
export type { SpendScale, SpendBands } from "./spendBands";
