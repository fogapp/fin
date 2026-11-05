import type { CandleRange } from "@/api/types";

/** Chart ranges accepted by the candles endpoint, in display order. */
export const CANDLE_RANGES: { value: CandleRange; label: string }[] = [
  { value: "1m", label: "1M" },
  { value: "3m", label: "3M" },
  { value: "6m", label: "6M" },
  { value: "ytd", label: "YTD" },
  { value: "1y", label: "1Y" },
  { value: "5y", label: "5Y" },
  { value: "max", label: "MAX" },
];

/** An overlay line drawn against the main series in percent-compare mode. */
export interface ComparisonSeries {
  key: string;
  label: string;
  color: string;
  prices: [string, number][];
}
