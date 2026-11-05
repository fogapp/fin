/**
 * Multi-series line chart (optional area fill when there is a single series).
 * Crosshair tooltip snaps to the nearest X and lists every series at that X.
 */
import { useId, useMemo, useRef } from "react";
import { useNavigate } from "react-router-dom";
import {
  LineChart as RLineChart, ComposedChart, Line, Area, CartesianGrid,
  XAxis, YAxis, Tooltip, Legend, ReferenceLine, ResponsiveContainer,
} from "recharts";
import { useChartTheme } from "./theme";
import { ChartTooltip } from "./ChartTooltip";
import {
  categoryAxisProps, curveFor, defaultTooltipLabel, defaultXTickFormat, defaultYFormat, legendProps,
  valueAxisProps, yearBoundaries, type ChartDatum, type ChartRow, type CurveMode, type SeriesDef,
} from "./common";

interface LineChartProps {
  data: object[];
  /** Ordered series list — palette slots are assigned by this order. */
  series: SeriesDef[];
  xKey?: string;
  height?: number;
  /** Fill under the line (single-series only). */
  area?: boolean;
  /**
   * Curve interpolation. "auto" (default) smooths dense daily series and
   * draws straight segments for sparse aggregates; override only when a
   * chart knows better.
   */
  curve?: CurveMode;
  yFormat?: (v: number) => string;
  valueFormat?: (v: number) => string;
  xTickFormat?: (v: string) => string;
  /** Format the tooltip header. */
  labelFormat?: (label: string) => string;
  /** Horizontal line at this y value (e.g. a period-start price). */
  referenceY?: number;
  referenceYLabel?: string;
  /** Show markers on every point (default: none; hover shows the active dot). */
  dots?: boolean;
  onSelect?: (datum: ChartDatum) => void;
  linkFor?: (datum: ChartDatum) => string | null;
}

export function LineChart({
  data: rawData, series, xKey = "month", height = 200, area = false, curve = "auto",
  yFormat, valueFormat, xTickFormat, labelFormat,
  referenceY, referenceYLabel, dots = false, onSelect, linkFor,
}: LineChartProps) {
  const data = rawData as ChartRow[];
  const curveType = curve === "auto" ? curveFor(data.length) : curve;
  const theme = useChartTheme();
  const navigate = useNavigate();
  const containerRef = useRef<HTMLDivElement>(null);
  const gradientId = useId();

  const boundaries = useMemo(() => yearBoundaries(data, xKey), [data, xKey]);
  const hasNegative = useMemo(
    () => data.some((row) => series.some((s) => typeof row[s.key] === "number" && (row[s.key] as number) < 0)),
    [data, series],
  );

  const interactive = Boolean(onSelect || linkFor);
  const singleArea = area && series.length === 1;
  const Chart = singleArea ? ComposedChart : RLineChart;

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
        <Chart
          data={data}
          onClick={interactive ? handleClick : undefined}
          style={interactive ? { cursor: "pointer" } : undefined}
        >
          {singleArea && (
            <defs>
              <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor={theme.series[0]} stopOpacity={0.18} />
                <stop offset="95%" stopColor={theme.series[0]} stopOpacity={0.02} />
              </linearGradient>
            </defs>
          )}
          <CartesianGrid vertical={false} stroke={theme.grid} strokeWidth={1} />
          <XAxis
            dataKey={xKey}
            {...categoryAxisProps(theme)}
            tickFormatter={(v: string) => (xTickFormat ?? defaultXTickFormat)(v)}
            interval="preserveStartEnd"
            minTickGap={24}
          />
          <YAxis
            {...valueAxisProps(theme)}
            width={48}
            tickFormatter={yFormat ?? defaultYFormat}
          />
          <Tooltip
            cursor={{ stroke: theme.muted, strokeWidth: 1, strokeDasharray: "3 3" }}
            isAnimationActive={false}
            content={<ChartTooltip labelFormat={labelFormat ?? defaultTooltipLabel} valueFormat={valueFormat} />}
          />
          {series.length > 1 && <Legend {...legendProps(theme)} />}
          {boundaries.map((x) => (
            <ReferenceLine key={x} x={x} stroke={theme.axis} strokeWidth={1} />
          ))}
          {hasNegative && <ReferenceLine y={0} stroke={theme.axis} strokeDasharray="3 3" />}
          {referenceY != null && (
            <ReferenceLine
              y={referenceY}
              stroke={theme.muted}
              strokeOpacity={0.6}
              strokeDasharray="3 5"
              label={referenceYLabel ? {
                value: referenceYLabel, position: "insideBottomRight", fontSize: 10, fill: theme.muted,
              } : undefined}
            />
          )}
          {singleArea && (
            <Area
              type={curveType}
              dataKey={series[0].key}
              name={series[0].label ?? series[0].key}
              stroke={theme.series[0]}
              strokeWidth={2}
              fill={`url(#${gradientId})`}
              dot={dots ? { r: 2, fill: theme.series[0], strokeWidth: 0 } : false}
              activeDot={{ r: 4 }}
              isAnimationActive={false}
            />
          )}
          {!singleArea && series.map((s, i) => {
            const color = s.color ?? theme.series[i] ?? theme.neutral;
            return (
              <Line
                key={s.key}
                type={curveType}
                dataKey={s.key}
                name={s.label ?? s.key}
                stroke={color}
                strokeWidth={2}
                dot={dots ? { r: 2, fill: color, strokeWidth: 0 } : false}
                activeDot={{ r: 4 }}
                connectNulls
                isAnimationActive={false}
              />
            );
          })}
        </Chart>
      </ResponsiveContainer>
    </div>
  );
}
