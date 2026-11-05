export type Period = "1M" | "6M" | "YTD" | "1Y" | "5Y" | "MAX";
export const PERIODS: Period[] = ["1M", "6M", "YTD", "1Y", "5Y", "MAX"];

// Volume is optional — pass [date, close] or [date, close, volume]
export type PriceData = [string, number, number][] | [string, number][];

export function cutoffFor(period: Period): string | null {
  if (period === "MAX") return null;
  const now = new Date();
  let d: Date;
  switch (period) {
    case "1M":  d = new Date(now.getFullYear(), now.getMonth() - 1, now.getDate()); break;
    case "6M":  d = new Date(now.getFullYear(), now.getMonth() - 6, now.getDate()); break;
    case "YTD": d = new Date(now.getFullYear(), 0, 1); break;
    case "1Y":  d = new Date(now.getFullYear() - 1, now.getMonth(), now.getDate()); break;
    case "5Y":  d = new Date(now.getFullYear() - 5, now.getMonth(), now.getDate()); break;
  }
  return d.toISOString().slice(0, 10);
}
