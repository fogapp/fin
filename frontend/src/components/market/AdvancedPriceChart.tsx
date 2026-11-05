/**
 * TradingView-style price chart built on lightweight-charts v5.
 *
 * Modes:
 * - Price: area (trend-colored against the range baseline) or candlesticks,
 *   with optional volume, SMA/EMA/Bollinger overlays, and RSI/MACD in
 *   stacked sub-panes.
 * - Compare: when comparison series are supplied the price scale switches
 *   to percent-change mode and every series renders as an indexed line
 *   (indicators/volume hide, as on Google Finance).
 *
 * The chart is fully rebuilt when data/options/theme change — datasets are
 * a few hundred points, so a rebuild is cheaper than reconciling series
 * lifecycles, and every rebuild re-fits the time scale.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import {
  createChart, createSeriesMarkers,
  AreaSeries, CandlestickSeries, HistogramSeries, LineSeries,
  ColorType, CrosshairMode, PriceScaleMode,
  type IChartApi, type ISeriesApi, type SeriesMarker, type Time, type UTCTimestamp,
} from "lightweight-charts";
import { BarChart3, LineChart as LineChartIcon, SlidersHorizontal } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Tabs } from "@/components/ui/tabs";
import { Skeleton } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuCheckboxItem, DropdownMenuLabel, DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import { useChartTheme } from "@/components/charts";
import { useLwcTheme } from "./lwcTheme";
import { sma, ema, rsi, macd, bollinger, type TimeValue } from "./indicators";
import { CANDLE_RANGES, type ComparisonSeries } from "./ranges";
import { cn, formatCurrency, formatCompactNumber, moneyColor } from "@/lib/utils";
import type { CandleData, CandleRange } from "@/api/types";

type ChartType = "area" | "candles";
type IndicatorKey = "sma50" | "sma200" | "ema20" | "bb" | "rsi" | "macd";

const INDICATORS: { key: IndicatorKey; label: string; pane: boolean }[] = [
  { key: "sma50",  label: "SMA 50",             pane: false },
  { key: "sma200", label: "SMA 200",            pane: false },
  { key: "ema20",  label: "EMA 20",             pane: false },
  { key: "bb",     label: "Bollinger (20, 2)",  pane: false },
  { key: "rsi",    label: "RSI (14)",           pane: true },
  { key: "macd",   label: "MACD (12, 26, 9)",   pane: true },
];

interface ChartPrefs {
  chartType: ChartType;
  volume: boolean;
  log: boolean;
  indicators: IndicatorKey[];
}

const PREFS_KEY = "market-chart-prefs";
const DEFAULT_PREFS: ChartPrefs = { chartType: "area", volume: true, log: false, indicators: [] };

function readPrefs(): ChartPrefs {
  try {
    const raw = localStorage.getItem(PREFS_KEY);
    return raw ? { ...DEFAULT_PREFS, ...JSON.parse(raw) } : DEFAULT_PREFS;
  } catch {
    return DEFAULT_PREFS;
  }
}

/**
 * Canvas 2D support probe, cached. jsdom (tests) has no canvas backend and
 * lightweight-charts crashes asynchronously there — the chart effect bails
 * out entirely instead.
 */
let canvasSupport: boolean | null = null;
function hasCanvasSupport(): boolean {
  if (canvasSupport != null) return canvasSupport;
  try {
    canvasSupport = typeof document !== "undefined" && document.createElement("canvas").getContext("2d") != null;
  } catch {
    canvasSupport = false;
  }
  return canvasSupport;
}

/** Resolve any CSS color to rgba with the given alpha (canvas-parsed). */
function withAlpha(color: string, alpha: number): string {
  if (!hasCanvasSupport()) return color;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1;
  const ctx = canvas.getContext("2d");
  if (!ctx) return color;
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/** "YYYY-MM-DD" → chart Time. Daily data uses date strings directly. */
function toTime(date: string): Time {
  return date as Time;
}

interface LegendState {
  date: string;
  o: number | null;
  h: number | null;
  l: number | null;
  c: number;
  v: number | null;
  changePct: number | null;
}

interface Props {
  data: CandleData | undefined;
  isLoading: boolean;
  range: CandleRange;
  onRangeChange: (range: CandleRange) => void;
  comparisons?: ComparisonSeries[];
  /** Toolbar slot rendered next to the range tabs (e.g. compare combobox). */
  toolbarExtra?: React.ReactNode;
  height?: number;
}

export function AdvancedPriceChart({
  data, isLoading, range, onRangeChange, comparisons = [], toolbarExtra, height = 360,
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const lwc = useLwcTheme();
  const palette = useChartTheme();

  const [prefs, setPrefs] = useState<ChartPrefs>(readPrefs);
  const [legend, setLegend] = useState<LegendState | null>(null);

  function updatePrefs(next: Partial<ChartPrefs>) {
    setPrefs((prev) => {
      const merged = { ...prev, ...next };
      try { localStorage.setItem(PREFS_KEY, JSON.stringify(merged)); } catch { /* private mode */ }
      return merged;
    });
  }

  const candles = useMemo(() => data?.candles ?? [], [data]);
  const hasOhlc = useMemo(
    () => candles.length > 0 && candles.filter((c) => c.o != null && c.h != null && c.l != null).length >= candles.length / 2,
    [candles],
  );
  const hasVolume = useMemo(() => candles.some((c) => (c.v ?? 0) > 0), [candles]);

  const compareMode = comparisons.length > 0;
  const chartType: ChartType = compareMode ? "area" : (hasOhlc ? prefs.chartType : "area");

  // Range baseline: previous close when the server has one, else the first
  // close in the window. Drives the area trend color.
  const baseline = data?.prev_close ?? candles[0]?.c ?? null;
  const lastClose = candles.at(-1)?.c ?? null;
  const trendUp = baseline == null || lastClose == null || lastClose >= baseline;

  const closesAsTimeValues = useMemo<TimeValue[]>(
    () => candles.map((c) => ({ time: c.t, value: c.c })),
    [candles],
  );

  const paneCount = compareMode ? 0 : prefs.indicators.filter((k) => INDICATORS.find((i) => i.key === k)?.pane).length;
  const totalHeight = height + paneCount * 100;

  const indicatorsKey = prefs.indicators.join(",");
  const comparisonsKey = comparisons.map((c) => `${c.key}:${c.prices.length}`).join("|");

  useEffect(() => {
    const container = containerRef.current;
    if (!container || !data || candles.length === 0 || !hasCanvasSupport()) return;

    let chart: IChartApi;
    try {
      chart = createChart(container, {
        autoSize: true,
        layout: {
          background: { type: ColorType.Solid, color: "transparent" },
          textColor: lwc.muted,
          panes: { separatorColor: lwc.border, enableResize: false },
        },
        grid: {
          vertLines: { visible: false },
          horzLines: { color: withAlpha(lwc.grid, 0.5) },
        },
        crosshair: {
          mode: CrosshairMode.Magnet,
          vertLine: { color: lwc.muted, labelBackgroundColor: lwc.muted },
          horzLine: { color: lwc.muted, labelBackgroundColor: lwc.muted },
        },
        rightPriceScale: {
          borderVisible: false,
          mode: compareMode ? PriceScaleMode.Percentage : (prefs.log ? PriceScaleMode.Logarithmic : PriceScaleMode.Normal),
          scaleMargins: { top: 0.08, bottom: prefs.volume && hasVolume && !compareMode ? 0.22 : 0.08 },
        },
        timeScale: { borderColor: lwc.border, rightOffset: 2 },
        handleScale: { axisPressedMouseMove: { time: true, price: false } },
      });
    } catch {
      // Canvas-less environments (jsdom) — leave the container empty.
      return;
    }

    const upColor = lwc.up;
    const downColor = lwc.down;
    const areaColor = trendUp ? upColor : downColor;

    let mainSeries: ISeriesApi<"Area"> | ISeriesApi<"Candlestick"> | ISeriesApi<"Line">;

    if (compareMode) {
      mainSeries = chart.addSeries(LineSeries, {
        color: lwc.primary, lineWidth: 2, priceLineVisible: false, lastValueVisible: true,
      });
      mainSeries.setData(candles.map((c) => ({ time: toTime(c.t), value: c.c })));
      // Benchmark payloads carry full downsampled history — clamp them to
      // this chart's window so the time scale stays put and the percent
      // baseline indexes both series from the same start.
      const windowStart = candles[0]?.t ?? "";
      for (const comp of comparisons) {
        const series = chart.addSeries(LineSeries, {
          color: comp.color, lineWidth: 2, priceLineVisible: false, lastValueVisible: true,
        });
        series.setData(
          comp.prices
            .filter(([date]) => date >= windowStart)
            .map(([date, close]) => ({ time: toTime(date), value: close })),
        );
      }
    } else if (chartType === "candles") {
      mainSeries = chart.addSeries(CandlestickSeries, {
        upColor, downColor, borderVisible: false,
        wickUpColor: upColor, wickDownColor: downColor,
      });
      mainSeries.setData(
        candles
          .filter((c) => c.o != null && c.h != null && c.l != null)
          .map((c) => ({ time: toTime(c.t), open: c.o!, high: c.h!, low: c.l!, close: c.c })),
      );
    } else {
      mainSeries = chart.addSeries(AreaSeries, {
        lineColor: areaColor, lineWidth: 2,
        topColor: withAlpha(areaColor, 0.2), bottomColor: withAlpha(areaColor, 0.02),
        priceLineVisible: false,
      });
      mainSeries.setData(candles.map((c) => ({ time: toTime(c.t), value: c.c })));
      if (baseline != null && data.prev_close != null) {
        mainSeries.createPriceLine({
          price: baseline, color: lwc.muted, lineWidth: 1, lineStyle: 3,
          axisLabelVisible: false, title: "prev close",
        });
      }
    }

    // ── Volume (overlay scale at the bottom of the main pane) ──
    if (!compareMode && prefs.volume && hasVolume) {
      const volumeSeries = chart.addSeries(HistogramSeries, {
        priceScaleId: "volume",
        priceFormat: { type: "volume" },
        priceLineVisible: false,
        lastValueVisible: false,
      });
      volumeSeries.priceScale().applyOptions({ scaleMargins: { top: 0.82, bottom: 0 } });
      volumeSeries.setData(candles.map((c, i) => ({
        time: toTime(c.t),
        value: c.v ?? 0,
        color: withAlpha(c.c >= (candles[i - 1]?.c ?? c.c) ? upColor : downColor, 0.35),
      })));
    }

    // ── Overlay indicators on the main pane ──
    if (!compareMode) {
      const overlays: { key: IndicatorKey; data: TimeValue[]; color: string; width?: number }[] = [];
      if (prefs.indicators.includes("sma50"))  overlays.push({ key: "sma50",  data: sma(closesAsTimeValues, 50),  color: palette.series[0] });
      if (prefs.indicators.includes("sma200")) overlays.push({ key: "sma200", data: sma(closesAsTimeValues, 200), color: palette.series[4] });
      if (prefs.indicators.includes("ema20"))  overlays.push({ key: "ema20",  data: ema(closesAsTimeValues, 20),  color: palette.series[2] });
      for (const overlay of overlays) {
        if (overlay.data.length === 0) continue;
        const series = chart.addSeries(LineSeries, {
          color: overlay.color, lineWidth: 1,
          priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false,
        });
        series.setData(overlay.data.map((p) => ({ time: toTime(p.time), value: p.value })));
      }

      if (prefs.indicators.includes("bb")) {
        const bands = bollinger(closesAsTimeValues, 20, 2);
        if (bands.length > 0) {
          const bandColor = withAlpha(palette.series[6], 0.8);
          for (const pick of ["upper", "middle", "lower"] as const) {
            const series = chart.addSeries(LineSeries, {
              color: pick === "middle" ? withAlpha(palette.series[6], 0.5) : bandColor,
              lineWidth: 1, lineStyle: pick === "middle" ? 3 : 0,
              priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false,
            });
            series.setData(bands.map((p) => ({ time: toTime(p.time), value: p[pick] })));
          }
        }
      }

      // ── Sub-pane indicators — pane indexes assigned contiguously so a
      // warm-up-starved indicator never leaves an empty pane behind ──
      const panes: ((paneIndex: number) => void)[] = [];

      const rsiData = prefs.indicators.includes("rsi") ? rsi(closesAsTimeValues, 14) : [];
      if (rsiData.length > 0) {
        panes.push((paneIndex) => {
          const series = chart.addSeries(LineSeries, {
            color: palette.series[4], lineWidth: 1, priceLineVisible: false, lastValueVisible: true,
          }, paneIndex);
          series.setData(rsiData.map((p) => ({ time: toTime(p.time), value: p.value })));
          for (const level of [30, 70]) {
            series.createPriceLine({
              price: level, color: withAlpha(lwc.muted, 0.5), lineWidth: 1, lineStyle: 3, axisLabelVisible: false,
            });
          }
        });
      }

      const macdData = prefs.indicators.includes("macd") ? macd(closesAsTimeValues) : [];
      if (macdData.length > 0) {
        panes.push((paneIndex) => {
          const histogram = chart.addSeries(HistogramSeries, {
            priceLineVisible: false, lastValueVisible: false,
          }, paneIndex);
          histogram.setData(macdData.map((p) => ({
            time: toTime(p.time), value: p.histogram,
            color: withAlpha(p.histogram >= 0 ? upColor : downColor, 0.5),
          })));
          const macdLine = chart.addSeries(LineSeries, {
            color: palette.series[0], lineWidth: 1, priceLineVisible: false, lastValueVisible: false,
          }, paneIndex);
          macdLine.setData(macdData.map((p) => ({ time: toTime(p.time), value: p.macd })));
          const signalLine = chart.addSeries(LineSeries, {
            color: palette.series[2], lineWidth: 1, priceLineVisible: false, lastValueVisible: false,
          }, paneIndex);
          signalLine.setData(macdData.map((p) => ({ time: toTime(p.time), value: p.signal })));
        });
      }

      panes.forEach((build, i) => {
        build(i + 1);
        chart.panes()[i + 1]?.setHeight(100);
      });

      // ── Corporate-action markers ──
      const markers: SeriesMarker<Time>[] = (data.events ?? [])
        .filter((e) => candles.some((c) => c.t === e.date))
        .map((e) => ({
          time: toTime(e.date),
          position: "belowBar" as const,
          color: e.kind === "split" ? lwc.primary : lwc.muted,
          shape: e.kind === "split" ? ("square" as const) : ("circle" as const),
          text: e.kind === "split"
            ? `Split ${e.ratio ?? ""}:1`
            : `Div ${e.amount != null ? formatCurrency(e.amount) : ""}`,
          size: 0.6,
        }));
      if (markers.length > 0) createSeriesMarkers(mainSeries, markers);
    }

    // ── Crosshair legend ──
    const byTime = new Map(candles.map((c) => [c.t, c]));
    const first = candles[0];
    const handler = (param: { time?: Time }) => {
      const t = param.time as string | UTCTimestamp | undefined;
      const point = typeof t === "string" ? byTime.get(t) : undefined;
      if (!point) {
        setLegend(null);
        return;
      }
      setLegend({
        date: point.t, o: point.o, h: point.h, l: point.l, c: point.c, v: point.v,
        changePct: first && first.c > 0 ? ((point.c - first.c) / first.c) * 100 : null,
      });
    };
    chart.subscribeCrosshairMove(handler);

    chart.timeScale().fitContent();

    return () => {
      chart.unsubscribeCrosshairMove(handler);
      chart.remove();
      setLegend(null);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- candles/closesAsTimeValues derive from data; indicatorsKey/comparisonsKey summarize their arrays
  }, [data, lwc, palette, chartType, compareMode, prefs.volume, prefs.log, indicatorsKey, comparisonsKey, trendUp, hasVolume]);

  if (isLoading) {
    return (
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <Skeleton className="h-7 w-40" />
          <Skeleton className="h-7 w-64" />
        </div>
        <Skeleton style={{ height: totalHeight }} className="w-full rounded-xl" />
      </div>
    );
  }

  const empty = !data || candles.length === 0;

  return (
    <div>
      {/* Toolbar */}
      <div className="mb-2 flex flex-wrap items-center gap-2">
        {!compareMode && (
          <>
            <Tabs<ChartType>
              size="sm"
              value={chartType}
              onChange={(v) => updatePrefs({ chartType: v })}
              options={[
                { value: "area", label: <LineChartIcon size={13} aria-label="Area chart" /> },
                ...(hasOhlc ? [{ value: "candles" as const, label: <BarChart3 size={13} aria-label="Candlestick chart" /> }] : []),
              ]}
            />
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="sm" className={cn("gap-1.5 text-xs", prefs.indicators.length > 0 && "text-primary")}>
                  <SlidersHorizontal size={13} />
                  Indicators
                  {prefs.indicators.length > 0 && <span className="tabular-nums">({prefs.indicators.length})</span>}
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start">
                <DropdownMenuLabel>Overlays</DropdownMenuLabel>
                {INDICATORS.filter((i) => !i.pane).map((ind) => (
                  <DropdownMenuCheckboxItem
                    key={ind.key}
                    checked={prefs.indicators.includes(ind.key)}
                    onCheckedChange={(checked) => updatePrefs({
                      indicators: checked
                        ? [...prefs.indicators, ind.key]
                        : prefs.indicators.filter((k) => k !== ind.key),
                    })}
                  >
                    {ind.label}
                  </DropdownMenuCheckboxItem>
                ))}
                <DropdownMenuSeparator />
                <DropdownMenuLabel>Oscillators</DropdownMenuLabel>
                {INDICATORS.filter((i) => i.pane).map((ind) => (
                  <DropdownMenuCheckboxItem
                    key={ind.key}
                    checked={prefs.indicators.includes(ind.key)}
                    onCheckedChange={(checked) => updatePrefs({
                      indicators: checked
                        ? [...prefs.indicators, ind.key]
                        : prefs.indicators.filter((k) => k !== ind.key),
                    })}
                  >
                    {ind.label}
                  </DropdownMenuCheckboxItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
            {hasVolume && (
              <Button
                variant="ghost" size="sm"
                className={cn("text-xs", prefs.volume ? "text-primary" : "text-muted-foreground")}
                onClick={() => updatePrefs({ volume: !prefs.volume })}
              >
                Vol
              </Button>
            )}
            <Button
              variant="ghost" size="sm"
              className={cn("text-xs", prefs.log ? "text-primary" : "text-muted-foreground")}
              onClick={() => updatePrefs({ log: !prefs.log })}
              title="Logarithmic price scale"
            >
              Log
            </Button>
          </>
        )}
        <div className="ml-auto flex items-center gap-2">
          {toolbarExtra}
          <Tabs<CandleRange>
            size="sm"
            value={range}
            onChange={onRangeChange}
            options={CANDLE_RANGES}
          />
        </div>
      </div>

      {/* Chart */}
      {empty ? (
        <EmptyState title="No price history yet." description="Prices sync shortly after a security is tracked." className="py-16" />
      ) : (
        <div className="relative" style={{ height: totalHeight }}>
          <div ref={containerRef} className="absolute inset-0" />
          {legend && (
            <div className="pointer-events-none absolute left-2 top-1.5 z-10 flex flex-wrap items-center gap-x-3 gap-y-0.5 rounded-md bg-card/85 px-2 py-1 text-caption tabular-nums text-muted-foreground backdrop-blur-sm">
              <span className="font-medium text-foreground">{legend.date}</span>
              {legend.o != null && legend.h != null && legend.l != null ? (
                <>
                  <span>O <span className="text-foreground">{formatCurrency(legend.o)}</span></span>
                  <span>H <span className="text-foreground">{formatCurrency(legend.h)}</span></span>
                  <span>L <span className="text-foreground">{formatCurrency(legend.l)}</span></span>
                  <span>C <span className="text-foreground">{formatCurrency(legend.c)}</span></span>
                </>
              ) : (
                <span><span className="text-foreground">{formatCurrency(legend.c)}</span></span>
              )}
              {legend.changePct != null && (
                <span className={moneyColor(legend.changePct)}>
                  {legend.changePct >= 0 ? "+" : ""}{legend.changePct.toFixed(2)}%
                </span>
              )}
              {legend.v != null && legend.v > 0 && (
                <span>Vol <span className="text-foreground">{formatCompactNumber(legend.v)}</span></span>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
