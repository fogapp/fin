/**
 * Stacked area chart — composition over time.
 *
 * Mark spec: bands filled at near-full opacity (a stack reads as parts of a
 * whole, not as overlapping translucent layers) separated by a 1px
 * surface-colored stroke, recessive horizontal-only grid, legend in series
 * order (which is also bottom-to-top stacking order).
 *
 * `percent` normalizes each x to 100%, answering "what share of this month
 * went where" instead of "how much" — the tooltip still reports dollars, with
 * each row's share beside it. Normalization can't represent negative values,
 * so the caller must pass non-negative data in percent mode.
 */
import { useMemo, useRef } from "react";
import { useNavigate } from "react-router-dom";
import {
  AreaChart as RAreaChart, Area, CartesianGrid,
  XAxis, YAxis, Tooltip, Legend, ReferenceLine, ResponsiveContainer,
} from "recharts";
import { useChartTheme } from "./theme";
import { ChartTooltip } from "./ChartTooltip";
import {
  categoryAxisProps, curveFor, defaultTooltipLabel, defaultXTickFormat, defaultYFormat, foldSeries,
  legendProps, slotColor, valueAxisProps, yearBoundaries,
  type ChartDatum, type ChartRow, type CurveMode, type SeriesDef,
} from "./common";

interface AreaChartProps {
  data: object[];
  /** Ordered series list — palette slots and stacking order (bottom-up). */
  series: SeriesDef[];
  xKey?: string;
  height?: number;
  /** Normalize each x to 100% — shares of the period rather than amounts. */
  percent?: boolean;
  /**
   * Curve interpolation. "auto" (default) smooths dense daily series and draws
   * straight segments for sparse aggregates — see `curveFor`.
   */
  curve?: CurveMode;
  yFormat?: (v: number) => string;
  valueFormat?: (v: number) => string;
  xTickFormat?: (v: string) => string;
  labelFormat?: (label: string) => string;
  /** Force the legend on/off; default: shown when >1 series. */
  legend?: boolean;
  onSelect?: (datum: ChartDatum) => void;
  linkFor?: (datum: ChartDatum) => string | null;
}

function percentTick(v: number): string {
  return `${Math.round(v * 100)}%`;
}

export function AreaChart({
  data: rawData, series: rawSeries, xKey = "month", height = 200,
  percent = false, curve = "auto",
  yFormat, valueFormat, xTickFormat, labelFormat, legend,
  onSelect, linkFor,
}: AreaChartProps) {
  const theme = useChartTheme();
  const navigate = useNavigate();
  const containerRef = useRef<HTMLDivElement>(null);

  // Fold a 9th+ series into "Other" — palette slots are never cycled.
  const { series, data } = useMemo(
    () => foldSeries(rawSeries, rawData as ChartRow[]),
    [rawSeries, rawData],
  );

  const curveType = curve === "auto" ? curveFor(data.length) : curve;
  const boundaries = useMemo(() => yearBoundaries(data, xKey), [data, xKey]);

  const interactive = Boolean(onSelect || linkFor);
  const showLegend = legend ?? series.length > 1;

  function handleClick(state: { activeLabel?: string | number } | null) {
    if (state?.activeLabel == null) return;
    const x = String(state.activeLabel);
    const row = data.find((r) => String(r[xKey]) === x) ?? {};
    const datum: ChartDatum = { x, row };
    onSelect?.(datum);
    const href = linkFor?.(datum);
    if (href) navigate(href);
    // Clear recharts' lingering hover highlight after click-through.
    setTimeout(() => {
      containerRef.current?.dispatchEvent(new MouseEvent("mouseleave", { bubbles: true }));
    }, 0);
  }

  return (
    <div ref={containerRef}>
      <ResponsiveContainer width="100%" height={height}>
        <RAreaChart
          data={data}
          stackOffset={percent ? "expand" : undefined}
          onClick={interactive ? handleClick : undefined}
          style={interactive ? { cursor: "pointer" } : undefined}
        >
          <CartesianGrid vertical={false} stroke={theme.grid} strokeWidth={1} />
          <XAxis
            dataKey={xKey}
            {...categoryAxisProps(theme)}
            tickFormatter={(v: string) => (xTickFormat ?? defaultXTickFormat)(v)}
            interval="preserveStartEnd"
            minTickGap={16}
          />
          <YAxis
            {...valueAxisProps(theme)}
            width={48}
            domain={percent ? [0, 1] : undefined}
            tickFormatter={yFormat ?? (percent ? percentTick : defaultYFormat)}
          />
          <Tooltip
            cursor={{ stroke: theme.muted, strokeWidth: 1, strokeDasharray: "3 3" }}
            isAnimationActive={false}
            content={(
              <ChartTooltip
                labelFormat={labelFormat ?? defaultTooltipLabel}
                valueFormat={valueFormat}
                hideZero={series.length > 1}
                withShare={percent}
              />
            )}
          />
          {showLegend && <Legend {...legendProps(theme, { matchSeriesOrder: true })} />}
          {boundaries.map((x) => (
            <ReferenceLine key={x} x={x} stroke={theme.axis} strokeWidth={1} />
          ))}
          {series.map((s, si) => {
            const color = slotColor(theme, series, si);
            return (
              <Area
                key={s.key}
                type={curveType}
                dataKey={s.key}
                name={s.label ?? s.key}
                stackId="stack"
                stroke={theme.surface}
                strokeWidth={1}
                fill={color}
                fillOpacity={0.9}
                activeDot={{ r: 3, stroke: theme.surface, strokeWidth: 1, fill: color }}
                isAnimationActive={false}
              />
            );
          })}
        </RAreaChart>
      </ResponsiveContainer>
    </div>
  );
}
