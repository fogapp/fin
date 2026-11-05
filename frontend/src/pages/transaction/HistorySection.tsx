import { formatCurrency, formatDate } from "@/lib/utils";
import type { CashTransaction, TransactionContext } from "@/api/types";
import { HistoryChart } from "./HistoryChart";
import { historyHeadline, peerLabel } from "./insights";
import { Section, TxnLine } from "./Section";

/** "Is this normal?" — the row among every charge like it. */
export function HistorySection({ tx, ctx }: { tx: CashTransaction; ctx: TransactionContext }) {
  if (ctx.history.basis === "none") {
    return (
      <Section id="history" eyebrow="History" headline="No description or merchant to compare this against." />
    );
  }

  const s = ctx.stats;
  const rows = ctx.history.rows;
  const idx = rows.findIndex((r) => r.id === tx.id);
  // The charges either side of this one (rows are oldest first; show newest first).
  const neighbors = rows.slice(Math.max(0, idx - 3), idx + 3).reverse();
  const hasExpected = !!(ctx.cadence?.includes_transaction || (ctx.series && ["active", "lapsed"].includes(ctx.series.status)));

  return (
    <Section
      id="history"
      eyebrow={ctx.history.basis === "merchant" ? `History at ${peerLabel(ctx)}` : "History of this description"}
      headline={historyHeadline(tx, ctx)}
    >
      {rows.length > 1 && <HistoryChart txId={tx.id} ctx={ctx} />}

      {s && (
        <dl className="flex flex-wrap gap-x-6 gap-y-1 text-xs">
          {s.count >= 3 && <Stat label="Usual" value={s.p25 === s.p75 ? formatCurrency(s.median) : `${formatCurrency(s.p25)} – ${formatCurrency(s.p75)}`} />}
          <Stat label="Past 12 months" value={`${formatCurrency(s.trailing_year_total)} · ${s.trailing_year_count} charge${s.trailing_year_count === 1 ? "" : "s"}`} />
          <Stat label="Since" value={formatDate(s.first_date)} />
          {hasExpected && (
            <span className="flex items-center gap-1.5 text-muted-foreground">
              <span aria-hidden className="inline-block size-2 rounded-full border border-dashed border-primary" />
              next expected
            </span>
          )}
        </dl>
      )}

      {neighbors.length > 1 && (
        <div className="divide-y overflow-hidden rounded-lg border">
          {neighbors.map((r) => (
            <TxnLine
              key={r.id}
              id={r.id}
              date={r.transaction_date}
              title={r.id === tx.id ? "This transaction" : r.description ?? "—"}
              detail={r.account_name}
              amount={r.amount}
              current={r.id === tx.id}
            />
          ))}
          {ctx.history.total > neighbors.length && (
            <p className="px-3 py-1.5 text-caption text-muted-foreground">
              {ctx.history.total - neighbors.length} more {ctx.history.total - neighbors.length === 1 ? "charge" : "charges"} in the chart
            </p>
          )}
        </div>
      )}
    </Section>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline gap-1.5">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="font-medium tabular-nums">{value}</dd>
    </div>
  );
}
