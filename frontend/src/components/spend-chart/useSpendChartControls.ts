/**
 * The spend chart's three mode toggles as one state bundle, so a page can
 * place the controls wherever it wants (its own header, or the card's) while
 * the chart consumes one object.
 *
 * `hashPersisted` puts the modes in the URL hash (Cashflow > Spending: saved
 * reports and shared URLs capture them; defaults stay out of the hash
 * entirely). The default is plain component state — detail pages already use
 * the hash for entity selection, and chart modes there aren't worth a URL.
 */
import { useState } from "react";
import { useHashParam } from "@/hooks/useHashParam";
import type { SpendScale } from "./spendBands";

/** "outlier" = spend as it actually happened; "common" = with flagged-outlier
 *  amounts subtracted; "both" overlays the two lines (Total mode only). */
export type SpendSeriesMode = "common" | "outlier" | "both";

/** What the chart splits its bars by — "none" is the single total line. */
export type SpendDimension = "none" | "category" | "merchant";

/** Toggle options for the series mode, exported for pages that render this
 *  control in their own header instead of the card's. */
export const SPEND_SERIES_OPTIONS: { value: SpendSeriesMode; label: string }[] = [
  { value: "common",  label: "Common" },
  { value: "outlier", label: "Outlier" },
  { value: "both",    label: "Both" },
];

export interface SpendChartControls {
  seriesMode: SpendSeriesMode;
  setSeriesMode: (mode: SpendSeriesMode) => void;
  dimension: SpendDimension;
  setDimension: (dimension: SpendDimension) => void;
  scale: SpendScale;
  setScale: (scale: SpendScale) => void;
}

export function useSpendChartControls({ hashPersisted = false, defaultDimension = "none" }: {
  hashPersisted?: boolean;
  defaultDimension?: SpendDimension;
} = {}): SpendChartControls {
  // Both state sources are wired unconditionally (hooks), then one is picked;
  // `hashPersisted` is constant per call site.
  const [seriesParam, setSeriesParam] = useHashParam("series", { replace: true });
  const [splitParam, setSplitParam] = useHashParam("split", { replace: true });
  const [scaleParam, setScaleParam] = useHashParam("scale", { replace: true });
  const [localSeries, setLocalSeries] = useState<SpendSeriesMode>("both");
  const [localDimension, setLocalDimension] = useState<SpendDimension>(defaultDimension);
  const [localScale, setLocalScale] = useState<SpendScale>("amount");

  if (!hashPersisted) {
    return {
      seriesMode: localSeries, setSeriesMode: setLocalSeries,
      dimension: localDimension, setDimension: setLocalDimension,
      scale: localScale, setScale: setLocalScale,
    };
  }
  return {
    seriesMode: seriesParam === "common" || seriesParam === "outlier" ? seriesParam : "both",
    setSeriesMode: (mode) => setSeriesParam(mode === "both" ? null : mode),
    dimension: splitParam === "category" || splitParam === "merchant" ? splitParam : "none",
    setDimension: (dimension) => setSplitParam(dimension === "none" ? null : dimension),
    scale: scaleParam === "share" ? "share" : "amount",
    setScale: (scale) => setScaleParam(scale === "amount" ? null : scale),
  };
}
