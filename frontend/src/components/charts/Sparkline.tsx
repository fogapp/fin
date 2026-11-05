/**
 * Minimal pure-SVG sparkline for stat cards. Deliberately not LineChart:
 * a grid of 15+ recharts ResponsiveContainers is heavy, and a sparkline
 * needs no grid, axes, or tooltip — the whole card is the interaction.
 *
 * The final segment renders dashed when the last point is partial
 * (in-progress period).
 */
import { useMemo } from "react";
import { useChartTheme } from "./theme";
import type { StatPoint } from "@/api/types";

interface SparklineProps {
  data: StatPoint[];
  height?: number;
  className?: string;
}

const W = 100;
const H = 28;
const PAD = 2;

export function Sparkline({ data, height = 36, className }: SparklineProps) {
  const theme = useChartTheme();

  const { solid, dashed } = useMemo(() => {
    const points = data.filter((p) => p.value != null);
    if (points.length < 2) return { solid: "", dashed: "" };

    const values = points.map((p) => p.value as number);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const span = max - min || 1;

    const coords = points.map((p, i) => {
      const x = PAD + (i / (points.length - 1)) * (W - PAD * 2);
      const y = PAD + (1 - ((p.value as number) - min) / span) * (H - PAD * 2);
      return `${x.toFixed(2)},${y.toFixed(2)}`;
    });

    // Dash the final segment when the series ends on an in-progress period.
    const lastPartial = points[points.length - 1]?.partial;
    if (lastPartial && coords.length > 2) {
      return {
        solid: coords.slice(0, -1).join(" "),
        dashed: coords.slice(-2).join(" "),
      };
    }
    return { solid: coords.join(" "), dashed: "" };
  }, [data]);

  if (!solid) return <div style={{ height }} className={className} />;

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      style={{ height, width: "100%" }}
      className={className}
      aria-hidden="true"
    >
      <polyline
        points={solid}
        fill="none"
        stroke={theme.series[0]}
        strokeWidth={1.5}
        vectorEffect="non-scaling-stroke"
      />
      {dashed && (
        <polyline
          points={dashed}
          fill="none"
          stroke={theme.series[0]}
          strokeWidth={1.5}
          strokeDasharray="3 3"
          vectorEffect="non-scaling-stroke"
        />
      )}
    </svg>
  );
}
