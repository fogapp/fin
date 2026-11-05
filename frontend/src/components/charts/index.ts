/**
 * Unified charting system. All charts share one theme (light/dark palettes
 * with fixed, never-cycled slot assignment), one tooltip, one timeframe
 * control, and one drill-down contract (`onSelect` / `linkFor` +
 * `transactionsHref`).
 */
export { ChartLabel } from "./ChartLabel";
export { ChartCard } from "./ChartCard";
export {
  useChartTheme, seriesColor, assignSeriesColors, chartModeFor, activityBucketColor,
  ACTIVITY_BUCKET_ORDER, LIGHT_SERIES, DARK_SERIES,
} from "./theme";
export type { ChartTheme, ChartMode } from "./theme";
export { ChartTooltip, TooltipShell, TooltipRow } from "./ChartTooltip";
export { TimeframeSelector } from "./TimeframeSelector";
export { SegmentedToggle } from "./SegmentedToggle";
export { useTimeframe, timeframeRange, builtinOption, iso as isoDate, TIMEFRAME_PRESETS, BUILTIN_TIMEFRAMES, BUILTIN_TIMEFRAME_KEYS } from "./timeframe";
export type { TimeframePreset, Timeframe, TimeframeOption, BuiltinTimeframe } from "./timeframe";
export { LineChart } from "./LineChart";
export { curveFor, DENSE_SERIES_THRESHOLD } from "./common";
export type { CurveMode } from "./common";
export { BarChart } from "./BarChart";
export { AreaChart } from "./AreaChart";
export { Sparkline } from "./Sparkline";
export { PieChart } from "./PieChart";
export type { PieSlice, PieDatum } from "./PieChart";
export { SankeyChart } from "./SankeyChart";
export type { SankeyNodeInput, SankeyLinkInput, SankeyNodeDatum, SankeyNodeKind, SankeyMember } from "./SankeyChart";
export { transactionsHref, monthDateRange } from "./links";
export type { TransactionsHrefParams } from "./links";
export type { SeriesDef, ChartDatum, ChartRow } from "./common";
export { defaultTooltipLabel } from "./common";
