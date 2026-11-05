import { useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { TooltipShell, TooltipRow } from "@/components/charts";
import { useElementWidth } from "@/hooks/useElementWidth";
import { formatCurrency, formatDate } from "@/lib/utils";
import type { TransactionContext, TransactionContextRow } from "@/api/types";

// ── History strip ─────────────────────────────────────────────────────────────
// Every peer charge as a dot on a time axis, with the usual range (the middle
// half of amounts) as a band and the median as a rule — so "is this normal?"
// and "does this repeat?" are both answered at a glance: an outlier sits above
// the band, a subscription shows as an evenly spaced row of dots. The current
// charge is the one emphasized mark; the next expected charge, when there's a
// cadence, is a hollow ring past the last dot.
//
// Plain SVG in real pixels (not a stretched viewBox) so dots stay round. One
// series, so no legend box — the section title names it; the hollow ring is
// keyed in the caption. Colors are semantic-token classes.

const HEIGHT = 176;
const PAD = { top: 16, right: 16, bottom: 24, left: 48 };
const DOT_R = 4;
const CURRENT_R = 6;
const HIT_RADIUS = 14;
// Past this many dots, marks shrink and lose their ring so a busy merchant
// (hundreds of coffees) reads as a density band instead of a smear.
const DENSE = 80;

interface Point { row: TransactionContextRow; x: number; y: number; current: boolean }

function toTime(date: string): number {
  return Date.UTC(+date.slice(0, 4), +date.slice(5, 7) - 1, +date.slice(8, 10));
}

/** 0 → max rounded up to a clean step, with three gridlines. */
function niceScale(max: number): number[] {
  if (max <= 0) return [0, 1];
  const raw = max / 3;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? raw;
  return [0, step, step * 2, step * 3];
}

function compactCurrency(v: number): string {
  return v >= 1000 ? formatCurrency(v, true) : formatCurrency(v).replace(/\.00$/, "");
}

function tickLabel(t: number, spanDays: number): string {
  const d = new Date(t);
  return spanDays > 400
    ? d.toLocaleDateString("en-US", { month: "short", year: "2-digit", timeZone: "UTC" })
    : d.toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
}

export function HistoryChart({ txId, ctx }: { txId: string; ctx: TransactionContext }) {
  const navigate = useNavigate();
  const wrapRef = useRef<HTMLDivElement>(null);
  const width = useElementWidth(wrapRef, 640);
  const [hover, setHover] = useState<Point | null>(null);

  const rows = ctx.history.rows;
  const expected = useMemo(() => (
    ctx.series?.next_expected_date && ["active", "lapsed"].includes(ctx.series.status)
      ? { date: ctx.series.next_expected_date, amount: ctx.series.average_amount }
      : ctx.cadence?.includes_transaction
        ? { date: ctx.cadence.next_expected_date, amount: ctx.cadence.average_amount }
        : null
  ), [ctx.series, ctx.cadence]);

  const geo = useMemo(() => {
    const times = rows.map((r) => toTime(r.transaction_date));
    if (expected) times.push(toTime(expected.date));
    let lo = Math.min(...times);
    let hi = Math.max(...times);
    // A lone date (or a same-day cluster) still needs an axis to sit on.
    if (hi - lo < 30 * 86_400_000) { lo -= 15 * 86_400_000; hi += 15 * 86_400_000; }
    const amounts = rows.map((r) => Math.abs(r.amount));
    if (expected) amounts.push(expected.amount);
    const ticks = niceScale(Math.max(...amounts) * 1.08);
    const yMax = ticks[ticks.length - 1];

    const plotW = Math.max(width - PAD.left - PAD.right, 40);
    const plotH = HEIGHT - PAD.top - PAD.bottom;
    const x = (t: number) => PAD.left + ((t - lo) / (hi - lo)) * plotW;
    const y = (v: number) => PAD.top + (1 - v / yMax) * plotH;

    const points: Point[] = rows.map((r) => ({
      row: r, x: x(toTime(r.transaction_date)), y: y(Math.abs(r.amount)), current: r.id === txId,
    }));
    const spanDays = (hi - lo) / 86_400_000;
    const xTicks = [lo, (lo + hi) / 2, hi];
    return { points, ticks, x, y, xTicks, spanDays, plotW };
  }, [rows, expected, width, txId]);

  const s = ctx.stats;
  const current = geo.points.find((p) => p.current);
  const dense = geo.points.length > DENSE;
  const dotR = dense ? 2.5 : DOT_R;
  const usual = s ? (s.p25 === s.p75 ? `usual ${compactCurrency(s.median)}` : `usual ${compactCurrency(s.p25)}–${compactCurrency(s.p75)}`) : "";

  function nearest(clientX: number, clientY: number): Point | null {
    const rect = wrapRef.current?.getBoundingClientRect();
    if (!rect) return null;
    const mx = clientX - rect.left;
    const my = clientY - rect.top;
    let best: Point | null = null;
    let bestD = HIT_RADIUS;
    for (const p of geo.points) {
      const d = Math.hypot(p.x - mx, p.y - my);
      if (d <= bestD) { best = p; bestD = d; }
    }
    return best;
  }

  return (
    <div
      ref={wrapRef}
      className="relative w-full select-none"
      onMouseMove={(e) => setHover(nearest(e.clientX, e.clientY))}
      onMouseLeave={() => setHover(null)}
      onClick={(e) => {
        const p = nearest(e.clientX, e.clientY);
        if (p && !p.current) navigate(`/transactions/${p.row.id}`);
      }}
      style={{ cursor: hover && !hover.current ? "pointer" : undefined }}
    >
      <svg width={width} height={HEIGHT} role="img" aria-label={`${ctx.history.total} charges over time; this one is highlighted`}>
        {/* Gridlines + y ticks */}
        {geo.ticks.map((t) => (
          <g key={t}>
            <line x1={PAD.left} x2={width - PAD.right} y1={geo.y(t)} y2={geo.y(t)} className="stroke-border" strokeWidth={1} />
            <text x={PAD.left - 8} y={geo.y(t)} dy="0.32em" textAnchor="end" className="fill-muted-foreground text-tiny tabular-nums">
              {compactCurrency(t)}
            </text>
          </g>
        ))}

        {/* Usual range (middle half) and the median */}
        {s && s.count >= 3 && (
          <>
            <rect
              x={PAD.left} width={geo.plotW}
              y={geo.y(s.p75)} height={Math.max(geo.y(s.p25) - geo.y(s.p75), 2)}
              className="fill-primary" fillOpacity={0.08}
            />
            <line x1={PAD.left} x2={width - PAD.right} y1={geo.y(s.median)} y2={geo.y(s.median)} className="stroke-primary" strokeOpacity={0.45} strokeWidth={1} />
            {/* Left end: the current charge is usually the newest, at the right. */}
            <text x={PAD.left + 4} y={geo.y(s.p75) - 5} className="fill-muted-foreground text-tiny">
              {usual}
            </text>
          </>
        )}

        {/* X ticks */}
        {geo.xTicks.map((t, i) => (
          <text
            key={i} x={geo.x(t)} y={HEIGHT - 6}
            textAnchor={i === 0 ? "start" : i === geo.xTicks.length - 1 ? "end" : "middle"}
            className="fill-muted-foreground text-tiny"
          >
            {tickLabel(t, geo.spanDays)}
          </text>
        ))}

        {/* Peer dots — surface ring keeps overlapping dots legible */}
        {geo.points.filter((p) => !p.current).map((p) => (
          <circle
            key={p.row.id} cx={p.x} cy={p.y} r={hover?.row.id === p.row.id ? dotR + 1.5 : dotR}
            className="fill-muted-foreground stroke-card" fillOpacity={dense ? 0.35 : 0.55} strokeWidth={dense ? 0 : 2}
          />
        ))}

        {/* Next expected charge */}
        {expected && (
          <circle
            cx={geo.x(toTime(expected.date))} cy={geo.y(expected.amount)} r={DOT_R + 0.5}
            className="fill-card stroke-primary" strokeWidth={1.5} strokeDasharray="2 2"
          />
        )}

        {/* This charge, labeled directly */}
        {current && (
          <g>
            <circle cx={current.x} cy={current.y} r={CURRENT_R} className="fill-primary stroke-card" strokeWidth={2} />
            <text
              x={current.x} y={current.y - CURRENT_R - 6}
              textAnchor={current.x > width - 80 ? "end" : current.x < PAD.left + 40 ? "start" : "middle"}
              className="fill-foreground stroke-card text-caption font-medium"
              strokeWidth={3} paintOrder="stroke"
            >
              This one
            </text>
          </g>
        )}
      </svg>

      {hover && (
        <div
          className="pointer-events-none absolute z-10"
          style={{
            left: Math.min(Math.max(hover.x - 80, 0), width - 170),
            top: Math.max(hover.y - 72, 0),
          }}
        >
          <TooltipShell label={formatDate(hover.row.transaction_date)}>
            <TooltipRow value={formatCurrency(hover.row.amount)} strong />
            {hover.row.account_name && <TooltipRow name={hover.row.account_name} value="" />}
            <p className="mt-0.5 text-tiny text-muted-foreground">
              {hover.current ? "This transaction" : "Click to open"}
            </p>
          </TooltipShell>
        </div>
      )}
    </div>
  );
}
