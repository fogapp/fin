/**
 * Tiny inline sparkline for market rows and index cards. Pure SVG (no
 * recharts container cost — these render 20+ per list) with the stroke
 * following the trend: positive/negative tokens by first→last direction,
 * so every theme colors it correctly.
 */
import { useMemo } from "react";

const W = 64;
const H = 20;
const PAD = 1.5;

interface Props {
  /** Closes, oldest → newest. */
  data: number[];
  width?: number;
  height?: number;
  className?: string;
}

export function TrendSparkline({ data, width = W, height = H, className }: Props) {
  const { points, up } = useMemo(() => {
    if (data.length < 2) return { points: "", up: true };
    const min = Math.min(...data);
    const max = Math.max(...data);
    const span = max - min || 1;
    const coords = data.map((v, i) => {
      const x = PAD + (i / (data.length - 1)) * (W - PAD * 2);
      const y = PAD + (1 - (v - min) / span) * (H - PAD * 2);
      return `${x.toFixed(2)},${y.toFixed(2)}`;
    });
    return { points: coords.join(" "), up: data[data.length - 1] >= data[0] };
  }, [data]);

  if (!points) return null;

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      style={{ width, height }}
      className={className}
      aria-hidden="true"
    >
      <polyline
        points={points}
        fill="none"
        stroke={up ? "var(--color-positive)" : "var(--color-negative)"}
        strokeWidth={1.5}
        strokeLinejoin="round"
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}
