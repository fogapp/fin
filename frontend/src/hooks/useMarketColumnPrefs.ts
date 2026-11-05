import { useQueryClient } from "@tanstack/react-query";
import { usePreferences } from "./usePreferences";
import { keys } from "@/api/keys";

export type MarketPrimary  = "ticker" | "name";
export type MarketSubtitle = "name" | "ticker" | "type" | "none";
export type MarketValue1   = "price" | "market_value" | "none";
export type MarketValue2   = "day_change" | "ytd_change" | "none";

export interface MarketColumnPrefs {
  primary:  MarketPrimary;
  subtitle: MarketSubtitle;
  value1:   MarketValue1;
  value2:   MarketValue2;
  /** Inline 30-day sparkline on each row. */
  sparkline: boolean;
}

const DEFAULTS: MarketColumnPrefs = {
  primary:  "ticker",
  subtitle: "name",
  value1:   "price",
  value2:   "day_change",
  sparkline: true,
};

function readLs(): MarketColumnPrefs {
  try {
    const raw = localStorage.getItem("market-column-prefs");
    return raw ? { ...DEFAULTS, ...JSON.parse(raw) } : DEFAULTS;
  } catch {
    return DEFAULTS;
  }
}

export function useMarketColumnPrefs() {
  const { prefs, set } = usePreferences();
  const qc = useQueryClient();

  const stored = (prefs.market_column as Partial<MarketColumnPrefs> | undefined) ?? readLs();
  const columnPrefs: MarketColumnPrefs = { ...DEFAULTS, ...stored };

  function setPrefs(next: Partial<MarketColumnPrefs>) {
    // Merge from the latest query-cache value (not the render-time snapshot) so
    // two setPrefs calls in the same render cycle don't drop the first update.
    let merged: MarketColumnPrefs = { ...DEFAULTS, ...next };
    qc.setQueryData<Record<string, unknown>>(keys.preferences, (old = {}) => {
      const current = (old.market_column as Partial<MarketColumnPrefs> | undefined) ?? readLs();
      merged = { ...DEFAULTS, ...current, ...next };
      return { ...old, market_column: merged };
    });
    localStorage.setItem("market-column-prefs", JSON.stringify(merged));
    set("market_column", merged);
  }

  return { prefs: columnPrefs, setPrefs };
}
