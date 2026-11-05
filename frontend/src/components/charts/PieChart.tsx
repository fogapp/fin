/**
 * Donut chart. Slices take palette slots in the fixed order of the data list
 * (never cycled — a 9th slice folds into "Other"). Top slices get direct
 * labels in normal ink; a legend always accompanies the donut. Hovered slices
 * lift with a muted outline; clicks pass the slice datum through.
 */
import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { PieChart as RPieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from "recharts";
import { useChartTheme } from "./theme";
import { ChartTooltip } from "./ChartTooltip";
import { legendProps, MAX_SLOTS } from "./common";

export interface PieSlice {
  name: string;
  value: number;
  /** Carried through to onSelect/linkFor (e.g. a category id). */
  id?: string;
}

export interface PieDatum extends PieSlice {
  /** True for the synthesized fold slice. */
  isOther?: boolean;
}

interface PieChartProps {
  data: PieSlice[];
  height?: number;
  valueFormat?: (v: number) => string;
  /** Direct-label slices at or above this share of the total (default 10%). */
  labelMinShare?: number;
  onSelect?: (datum: PieDatum) => void;
  linkFor?: (datum: PieDatum) => string | null;
}

export function PieChart({
  data, height = 200, valueFormat, labelMinShare = 0.1, onSelect, linkFor,
}: PieChartProps) {
  const theme = useChartTheme();
  const navigate = useNavigate();
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  // ≤8 slices get palette slots; the rest fold into a neutral "Other".
  const slices = useMemo<PieDatum[]>(() => {
    if (data.length <= MAX_SLOTS) return data;
    const kept = data.slice(0, MAX_SLOTS - 1);
    const other = data.slice(MAX_SLOTS - 1).reduce((s, d) => s + d.value, 0);
    return [...kept, { name: "Other", value: other, isOther: true }];
  }, [data]);

  const total = useMemo(() => slices.reduce((s, d) => s + d.value, 0), [slices]);
  const interactive = Boolean(onSelect || linkFor);

  function sliceColor(index: number): string {
    return slices[index]?.isOther ? theme.neutral : theme.series[index] ?? theme.neutral;
  }

  function handleClick(_: unknown, index: number) {
    const datum = slices[index];
    if (!datum) return;
    onSelect?.(datum);
    const href = linkFor?.(datum);
    if (href) navigate(href);
  }

  // Direct labels in normal ink — identity never rides on color alone.
  interface LabelProps { x?: number; y?: number; textAnchor?: "start" | "middle" | "end" | "inherit"; value?: number; name?: string; index?: number }
  function renderLabel({ x, y, textAnchor, value, name }: LabelProps) {
    if (total <= 0 || (value ?? 0) / total < labelMinShare) return null;
    return (
      <text x={x} y={y} textAnchor={textAnchor} dominantBaseline="central" fontSize={10} fill={theme.muted}>
        {name}
      </text>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={height}>
      <RPieChart>
        <Pie
          data={slices}
          dataKey="value"
          nameKey="name"
          cx="50%"
          cy="50%"
          innerRadius="55%"
          outerRadius="80%"
          paddingAngle={1}
          label={renderLabel}
          labelLine={{ stroke: theme.grid }}
          isAnimationActive={false}
          onClick={interactive ? handleClick : undefined}
          onMouseEnter={(_: unknown, index: number) => setActiveIndex(index)}
          onMouseLeave={() => setActiveIndex(null)}
          style={interactive ? { cursor: "pointer", outline: "none" } : { outline: "none" }}
        >
          {slices.map((_, i) => (
            <Cell
              key={i}
              fill={sliceColor(i)}
              stroke={activeIndex === i ? theme.muted : theme.surface}
              strokeWidth={activeIndex === i ? 1.5 : 2}
              fillOpacity={activeIndex === i ? 0.92 : 1}
            />
          ))}
        </Pie>
        <Tooltip
          isAnimationActive={false}
          content={<ChartTooltip valueFormat={valueFormat} showTotal={false} />}
        />
        <Legend {...legendProps(theme)} iconType="circle" iconSize={8} />
      </RPieChart>
    </ResponsiveContainer>
  );
}
