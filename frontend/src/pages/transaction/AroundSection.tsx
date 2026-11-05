import { formatCurrency } from "@/lib/utils";
import type { CashTransaction, TransactionContext } from "@/api/types";
import { relativeDays } from "./insights";
import { Section, TxnLine } from "./Section";

/** What happened next to it: the refund (or the charge a refund reverses),
 *  and the rest of the day — often the only way to remember what a trip was. */
export function AroundSection({ tx, ctx }: { tx: CashTransaction; ctx: TransactionContext }) {
  const { related, same_day: day } = ctx;
  if (related.length === 0 && day.total === 0) return null;

  // Spending that day, this charge included — only when every row is in hand.
  const daySpend = day.total === day.rows.length
    ? [...day.rows, tx].filter((r) => r.amount < 0 && !r.transfer_id).reduce((s, r) => s - r.amount, 0)
    : null;

  return (
    <Section
      id="around"
      eyebrow="Around this charge"
      headline={day.total > 0
        ? <>{day.total} other transaction{day.total === 1 ? "" : "s"} the same day{daySpend != null && daySpend > 0 && <> — {formatCurrency(daySpend)} spent in all</>}.</>
        : undefined}
    >
      {related.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs font-medium text-muted-foreground">
            {tx.amount < 0 ? "Money back from this merchant" : "Charges this may reverse"}
          </p>
          <div className="divide-y overflow-hidden rounded-lg border">
            {related.map((r) => (
              <TxnLine
                key={r.id}
                id={r.id}
                date={r.transaction_date}
                title={r.description ?? "—"}
                detail={relativeDays(r.date_diff)}
                amount={r.amount}
              />
            ))}
          </div>
        </div>
      )}

      {day.total > 0 && (
        <div className="space-y-1.5">
          {related.length > 0 && <p className="text-xs font-medium text-muted-foreground">Same day</p>}
          <div className="divide-y overflow-hidden rounded-lg border">
            {day.rows.map((r) => (
              <TxnLine
                key={r.id}
                id={r.id}
                date={r.transaction_date}
                title={r.merchant_name ?? r.description ?? "—"}
                detail={[r.category_name, r.account_name].filter(Boolean).join(" · ") || undefined}
                amount={r.amount}
              />
            ))}
            {day.total > day.rows.length && (
              <p className="px-3 py-1.5 text-caption text-muted-foreground">+ {day.total - day.rows.length} smaller</p>
            )}
          </div>
        </div>
      )}
    </Section>
  );
}
