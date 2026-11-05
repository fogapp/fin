import { Link } from "react-router-dom";
import { cn, formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import type { InsightTarget } from "./insights";

/** One part of the page's story: a quiet eyebrow, a headline sentence that
 *  says what the section found, then whatever shows it. No card chrome — the
 *  sections are separated by space and a hairline, not boxes. */
export function Section({ id, eyebrow, headline, aside, children, className }: {
  id: InsightTarget;
  eyebrow: string;
  headline?: React.ReactNode;
  aside?: React.ReactNode;
  children?: React.ReactNode;
  className?: string;
}) {
  return (
    <section id={`txn-${id}`} aria-label={eyebrow} className={cn("scroll-mt-20 space-y-3 py-6 first:pt-0", className)}>
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <p className="text-caption font-medium uppercase tracking-wide text-muted-foreground">{eyebrow}</p>
          {headline && <p className="text-base font-medium leading-snug text-foreground">{headline}</p>}
        </div>
        {aside && <div className="shrink-0">{aside}</div>}
      </div>
      {children}
    </section>
  );
}

/** A compact, linked transaction line: date · what · where · amount. */
export function TxnLine({ id, date, title, detail, amount, current = false, trailing }: {
  id: string;
  date: string;
  title: React.ReactNode;
  detail?: React.ReactNode;
  amount: number;
  current?: boolean;
  trailing?: React.ReactNode;
}) {
  const body = (
    <>
      <span className="w-24 shrink-0 tabular-nums text-muted-foreground">{formatDate(date)}</span>
      <span className="min-w-0 flex-1 truncate">
        {title}
        {detail && <span className="text-muted-foreground"> · {detail}</span>}
      </span>
      {trailing}
      <span className={cn("shrink-0 tabular-nums font-medium", moneyColor(amount))}>{formatCurrency(amount)}</span>
    </>
  );
  const cls = "flex items-center gap-3 px-3 py-2 text-xs";
  if (current) {
    return <div className={cn(cls, "bg-primary/8 font-medium")} aria-current="true">{body}</div>;
  }
  return (
    <Link
      to={`/transactions/${id}`}
      className={cn(cls, "transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary")}
    >
      {body}
    </Link>
  );
}
