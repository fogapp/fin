// ── Market-data formatting helpers ────────────────────────────────────────────

import type { InstrumentClass, PriceSource } from "@/api/types";

const CLASS_LABELS: Record<InstrumentClass, string> = {
  equity: "Equity",
  etf: "ETF",
  mutual_fund: "Fund",
  bond: "Bond",
  cash_equivalent: "Cash",
  crypto: "Crypto",
  commodity: "Commodity",
  option: "Option",
  fx: "FX",
  real_asset: "Real asset",
  other: "Other",
};

export function instrumentClassLabel(instrumentClass: InstrumentClass): string {
  return CLASS_LABELS[instrumentClass] ?? instrumentClass;
}

const SOURCE_LABELS: Record<PriceSource, string> = {
  coin_market_cap: "CoinMarketCap",
  alpha_vantage: "Alpha Vantage",
  coin_gecko: "CoinGecko",
  tiingo: "Tiingo",
  eod: "End-of-day feed",
  legacy: "Legacy price history",
  custodian: "Custodian-reported",
};

export function priceSourceLabel(source: string): string {
  return SOURCE_LABELS[source as PriceSource] ?? source.replace(/_/g, " ");
}

export interface StalenessPrice {
  date: string;
  source?: PriceSource;
  age_days?: number;
}

/** Whole days since the price was observed; falls back to the price date when
 *  the payload doesn't carry age_days (the security show endpoint). */
export function priceAgeDays(price: StalenessPrice): number {
  if (price.age_days != null) return price.age_days;
  return Math.max(0, Math.floor((Date.now() - new Date(price.date).getTime()) / 86_400_000));
}
