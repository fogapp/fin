/**
 * Grouped / stacked bar chart (vertical or horizontal bars).
 *
 * Mark spec: 4px rounded corners on the value end only (anchored baseline),
 * a 2px surface-colored stroke so stacked segments and adjacent bars read as
 * separate fills, recessive horizontal-only grid, hovered column lifts.
 */
import { useMemo, useRef } from "react";
import { useNavigate } from "react-router-dom";
import {
  BarChart as RBarChart, Bar, Cell, CartesianGrid,
  XAxis, YAxis, Tooltip, Legend, ReferenceLine, ResponsiveContainer,
} from "recharts";
import { useChartTheme } from "./theme";
import { ChartTooltip } from "./ChartTooltip";
import {
  categoryAxisProps, defaultTooltipLabel, defaultXTickFormat, defaultYFormat, foldSeries, valueAxisProps,
  legendProps, slotColor, yearBoundaries,
  type ChartDatum, type ChartRow, type SeriesDef,
} from "./common";

type Radius = [number, number, number, number];

interface BarChartProps {
  data: object[];
  /** Ordered series list — palette slots are assigned by this order. */
  series: SeriesDef[];
  xKey?: string;
  height?: number;
  stacked?: boolean;
  /** Bar direction: "vertical" bars grow up (default); "horizontal" grow right. */
  orientation?: "vertical" | "horizontal";
  /** Single-series polarity coloring: blue positive / red negative. */
  diverging?: boolean;
  /** De-emphasize all bars except the one whose x equals this value. */
  highlightX?: string;
  /** Render the bar whose x equals this value at reduced opacity — the
   *  honest treatment for an in-progress (partial) period. */
  partialX?: string;
  yFormat?: (v: number) => string;
  valueFormat?: (v: number) => string;
  xTickFormat?: (v: string) => string;
  labelFormat?: (label: string) => string;
  /** Force the legend on/off; default: shown when >1 series. */
  legend?: boolean;
  onSelect?: (datum: ChartDatum) => void;
  linkFor?: (datum: ChartDatum) => string | null;
}

export function BarChart({
  data: rawData, series: rawSeries, xKey = "month", height = 200,
  stacked = false, orientation = "vertical", diverging = false, highlightX, partialX,
  yFormat, valueFormat, xTickFormat, labelFormat, legend,
  onSelect, linkFor,
}: BarChartProps) {
  const theme = useChartTheme();
  const navigate = useNavigate();
  const containerRef = useRef<HTMLDivElement>(null);

  // Fold a 9th+ series into "Other" — palette slots are never cycled.
  const { series, data } = useMemo(
    () => foldSeries(rawSeries, rawData as ChartRow[]),
    [rawSeries, rawData],
  );

  const horizontal = orientation === "horizontal";
  const boundaries = useMemo(() => (horizontal ? [] : yearBoundaries(data, xKey)), [data, xKey, horizontal]);
  const hasNegative = useMemo(
    () => data.some((row) => series.some((s) => typeof row[s.key] === "number" && (row[s.key] as number) < 0)),
    [data, series],
  );

  const interactive = Boolean(onSelect || linkFor);
  const showLegend = legend ?? series.length > 1;

  function radiusFor(seriesIndex: number, value: number): Radius {
    // Rounded on the value end only; stacked interior segments stay square.
    if (stacked && seriesIndex !== series.length - 1) return [0, 0, 0, 0];
    if (horizontal) return value < 0 ? [4, 0, 0, 4] : [0, 4, 4, 0];
    return value < 0 ? [0, 0, 4, 4] : [4, 4, 0, 0];
  }

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

  function cellFill(seriesIndex: number, value: number): string {
    if (diverging && series.length === 1) return value < 0 ? theme.negative : theme.positive;
    return slotColor(theme, series, seriesIndex);
  }

  const numberAxisProps = {
    ...valueAxisProps(theme),
    tickFormatter: yFormat ?? defaultYFormat,
  } as const;
  const categoryProps = {
    dataKey: xKey,
    ...categoryAxisProps(theme),
    tickFormatter: (v: string) => (xTickFormat ?? defaultXTickFormat)(v),
  } as const;

  return (
    <div ref={containerRef}>
      <ResponsiveContainer width="100%" height={height}>
        <RBarChart
          data={data}
          layout={horizontal ? "vertical" : "horizontal"}
          onClick={interactive ? handleClick : undefined}
          style={interactive ? { cursor: "pointer" } : undefined}
        >
          <CartesianGrid vertical={horizontal} horizontal={!horizontal} stroke={theme.grid} strokeWidth={1} />
          {horizontal ? (
            <>
              <XAxis type="number" {...numberAxisProps} />
              <YAxis type="category" {...categoryProps} width={48} interval={0} />
            </>
          ) : (
            <>
              <XAxis {...categoryProps} interval="preserveStartEnd" minTickGap={16} />
              <YAxis {...numberAxisProps} width={48} />
            </>
          )}
          <Tooltip
            cursor={{ fill: "currentColor", fillOpacity: 0.05 }}
            isAnimationActive={false}
            position={horizontal ? undefined : { y: 4 }}
            content={(
              <ChartTooltip
                labelFormat={labelFormat ?? defaultTooltipLabel}
                valueFormat={valueFormat}
                hideZero={series.length > 1}
              />
            )}
          />
          {showLegend && <Legend {...legendProps(theme, { matchSeriesOrder: stacked })} />}
          {boundaries.map((x) => (
            <ReferenceLine key={x} x={x} stroke={theme.axis} strokeWidth={1} />
          ))}
          {(hasNegative || diverging) && (
            horizontal
              ? <ReferenceLine x={0} stroke={theme.axis} />
              : <ReferenceLine y={0} stroke={theme.axis} />
          )}
          {series.map((s, si) => (
            <Bar
              key={s.key}
              dataKey={s.key}
              name={s.label ?? s.key}
              stackId={stacked ? "stack" : undefined}
              fill={slotColor(theme, series, si)}
              stroke={theme.surface}
              strokeWidth={2}
              radius={radiusFor(si, 1)}
              isAnimationActive={false}
              activeBar={{ stroke: theme.muted, strokeWidth: 1.5, fillOpacity: 0.92 }}
            >
              {(diverging || hasNegative || highlightX != null || partialX != null) && data.map((row, i) => {
                const value = typeof row[s.key] === "number" ? (row[s.key] as number) : 0;
                const dimmed = highlightX != null && String(row[xKey]).slice(0, highlightX.length) !== highlightX;
                const partial = partialX != null && String(row[xKey]) === partialX;
                return (
                  <Cell
                    key={i}
                    fill={cellFill(si, value)}
                    fillOpacity={dimmed ? 0.3 : partial ? 0.45 : 1}
                    radius={radiusFor(si, value) as unknown as number}
                  />
                );
              })}
            </Bar>
          ))}
        </RBarChart>
      </ResponsiveContainer>
    </div>
  );
}
