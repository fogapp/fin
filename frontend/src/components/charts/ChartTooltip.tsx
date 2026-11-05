/**
 * The one shared tooltip for every chart type.
 *
 * Rows put the VALUE first visually (strong, high-contrast); the series name is
 * secondary and keyed by a short stroke of the series color (not a filled box).
 * Multi-series tooltips add a Total row. Labels/values always wear normal ink —
 * never the series color. All text goes through React's default escaping
 * (never dangerouslySetInnerHTML), which covers untrusted labels.
 */
import { formatCurrency } from "@/lib/utils";

// ── Presentational shell (also used by the Sankey link/node tooltips) ─────────

export function TooltipShell({ label, children }: {
  label?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="pointer-events-none rounded-lg border bg-card px-2.5 py-1.5 text-xs text-card-foreground shadow-md">
      {label != null && label !== "" && (
        <p className="mb-1 font-medium text-muted-foreground">{label}</p>
      )}
      {children}
    </div>
  );
}

export function TooltipRow({ color, name, value, strong = false }: {
  color?: string;
  name?: React.ReactNode;
  value: React.ReactNode;
  strong?: boolean;
}) {
  return (
    <div className="flex items-center gap-2">
      {color != null && (
        <span aria-hidden className="h-0.5 w-3 shrink-0 rounded-full" style={{ background: color }} />
      )}
      {name != null && name !== "" && <span className="text-muted-foreground">{name}</span>}
      <span className={`ml-auto pl-3 tabular-nums ${strong ? "font-semibold" : "font-medium"}`}>{value}</span>
    </div>
  );
}

// ── Recharts adapter ──────────────────────────────────────────────────────────

export interface TooltipPayloadEntry {
  name?: string | number;
  value?: number | string;
  color?: string;
  stroke?: string;
  fill?: string;
  dataKey?: string | number;
  payload?: Record<string, unknown>;
}

export interface ChartTooltipProps {
  active?: boolean;
  payload?: ReadonlyArray<TooltipPayloadEntry>;
  label?: string | number;
  /** Format the header label (e.g. month/date). */
  labelFormat?: (label: string) => string;
  /** Format row values (default: currency). */
  valueFormat?: (v: number) => string;
  /** Drop zero-valued rows (useful for sparse stacked bars). */
  hideZero?: boolean;
  /** Append each row's share of the total (for normalized/percent charts,
   *  where the mark encodes the share but the number people want is both). */
  withShare?: boolean;
  /** Force the Total row on/off; default: shown when >1 row. */
  showTotal?: boolean;
  totalLabel?: string;
  /** Override the computed total (e.g. NetWorth's "Net" line). */
  totalValue?: number;
}

export function ChartTooltip({
  active, payload, label,
  labelFormat, valueFormat, hideZero = false, withShare = false,
  showTotal, totalLabel = "Total", totalValue,
}: ChartTooltipProps) {
  if (!active || !payload?.length) return null;

  const fmt = valueFormat ?? ((v: number) => formatCurrency(v));
  const entries = payload
    .filter((e) => typeof e.value === "number" && Number.isFinite(e.value))
    .filter((e) => !hideZero || (e.value as number) !== 0);
  if (entries.length === 0) return null;

  const multi = entries.length > 1;
  const total = totalValue ?? entries.reduce((s, e) => s + (e.value as number), 0);
  const withTotal = showTotal ?? multi;
  const header = label != null ? (labelFormat ? labelFormat(String(label)) : String(label)) : undefined;

  return (
    <TooltipShell label={header}>
      {entries.map((e, i) => (
        <TooltipRow
          key={`${String(e.dataKey ?? e.name)}-${i}`}
          color={e.color ?? e.stroke ?? e.fill}
          name={multi ? String(e.name ?? e.dataKey ?? "") : undefined}
          value={
            withShare && total !== 0 ? (
              <>
                {fmt(e.value as number)}
                <span className="ml-1.5 font-normal text-muted-foreground">
                  {((e.value as number) / total * 100).toFixed(0)}%
                </span>
              </>
            ) : fmt(e.value as number)
          }
        />
      ))}
      {withTotal && (
        <div className="mt-1 border-t pt-1">
          <TooltipRow name={totalLabel} value={fmt(total)} strong />
        </div>
      )}
    </TooltipShell>
  );
}
