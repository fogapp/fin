import { Link } from "react-router-dom";
import { cn, formatCurrency, formatMonthLabel } from "@/lib/utils";
import type { TransactionContext } from "@/api/types";
import { shareLabel } from "./insights";
import { Section } from "./Section";

type Budget = NonNullable<TransactionContext["budget"]>;

function monthName(month: string): string {
  return new Date(`${month}-02`).toLocaleDateString("en-US", { month: "long" });
}

/** What this charge did to the budget line it landed on that month. */
export function BudgetSection({ ctx }: { ctx: TransactionContext }) {
  const b = ctx.budget;
  if (!b) return null;

  const name = b.scope === "line" ? b.category_name ?? "this budget" : "everything else";
  const when = b.period === "yearly" ? `this year` : `in ${monthName(b.month)}`;

  if (b.available == null) {
    return (
      <Section
        id="budget"
        eyebrow="Budget"
        headline={<>No budget covers this. It's part of {formatCurrency(b.actual)} of unbudgeted spending {when}.</>}
      >
        <Link to="/budget" className="text-xs text-primary underline-offset-2 hover:underline">Plan a budget</Link>
      </Section>
    );
  }

  const share = b.available > 0 ? b.contribution / b.available : 0;
  const over = b.actual > b.available;
  const headline = b.contribution < 0
    ? <>This gave {formatCurrency(-b.contribution)} back to {name} {when}{b.remaining != null && <>, leaving {formatCurrency(b.remaining)}</>}.</>
    : over
    ? b.before > b.available
      ? <>{cap(name)} was already over budget {when}; this added {formatCurrency(b.contribution)}.</>
      : <>This pushed {name} over budget {when} — {formatCurrency(b.actual - b.available)} over.</>
    : <>This used {shareLabel(share)} of {name} {when}, leaving {formatCurrency(b.remaining ?? b.available - b.actual)}.</>;

  return (
    <Section id="budget" eyebrow={`Budget · ${cap(name)}`} headline={headline}>
      <BudgetMeter budget={b} />
      {b.history.length > 1 && <BudgetHistory budget={b} />}
    </Section>
  );
}

function cap(s: string) { return s.charAt(0).toUpperCase() + s.slice(1); }

/** Spent before · this charge · what's left, on one track scaled to the larger of plan and actual. */
function BudgetMeter({ budget: b }: { budget: Budget }) {
  const available = b.available ?? 0;
  const scale = Math.max(available, b.actual, 1);
  const pct = (v: number) => `${Math.max(0, Math.min(100, (v / scale) * 100))}%`;
  const before = Math.max(b.before, 0);
  const thisPart = Math.max(b.contribution, 0);
  const withinPlan = Math.max(Math.min(before + thisPart, available) - before, 0);
  const overPart = Math.max(before + thisPart - Math.max(available, before), 0);

  return (
    <div className="space-y-2">
      <div className="relative h-3 overflow-hidden rounded-full bg-primary/10" role="img"
        aria-label={`${formatCurrency(b.before)} spent before, ${formatCurrency(b.contribution)} this charge, of ${formatCurrency(available)}`}>
        <div className="absolute inset-y-0 left-0 bg-primary/35" style={{ width: pct(before) }} />
        <div className="absolute inset-y-0 border-l-2 border-card bg-primary" style={{ left: pct(before), width: pct(withinPlan) }} />
        {overPart > 0 && (
          <div className="absolute inset-y-0 border-l-2 border-card bg-negative"
            style={{ left: pct(Math.max(available, before)), width: pct(overPart) }} />
        )}
        {b.actual > available && available > 0 && (
          <div className="absolute inset-y-0 w-0.5 bg-foreground" style={{ left: pct(available) }} aria-hidden />
        )}
      </div>
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
        <Key className="bg-primary/35" label="Before" value={formatCurrency(b.before)} />
        <Key className="bg-primary" label="This" value={formatCurrency(b.contribution)} />
        <span className="ml-auto tabular-nums text-muted-foreground">
          {formatCurrency(b.actual)} of {formatCurrency(available)}
          {b.typical != null && b.typical > 0 && <> · typical month {formatCurrency(b.typical)}</>}
        </span>
      </div>
    </div>
  );
}

function Key({ className, label, value }: { className: string; label: string; value: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span aria-hidden className={cn("size-2 rounded-full", className)} />
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium tabular-nums">{value}</span>
    </span>
  );
}

/** Six months of the line — actual columns against the plan's tick, this month emphasized. */
function BudgetHistory({ budget: b }: { budget: Budget }) {
  const max = Math.max(...b.history.map((h) => Math.max(h.actual, h.planned)), 1);
  return (
    <div className="space-y-1.5">
      <div className="flex h-16 items-end gap-2" role="img" aria-label="Spending against plan, last six months">
        {b.history.map((h) => {
          const current = h.month === b.month;
          const over = h.planned > 0 && h.actual > h.planned;
          return (
            <div key={h.month} className="relative flex h-full flex-1 items-end justify-center" title={`${formatMonthLabel(h.month)}: ${formatCurrency(h.actual)} of ${formatCurrency(h.planned)}`}>
              <div
                className={cn("w-full max-w-6 rounded-t", current ? (over ? "bg-negative" : "bg-primary") : "bg-muted-foreground/30")}
                style={{ height: `${(h.actual / max) * 100}%` }}
              />
              {h.planned > 0 && (
                <div className="absolute left-1/2 h-0.5 w-8 max-w-full -translate-x-1/2 rounded-full bg-foreground/70" style={{ bottom: `${(h.planned / max) * 100}%` }} aria-hidden />
              )}
            </div>
          );
        })}
      </div>
      {/* Size on the wrapper: cn()'s tailwind-merge reads text-tiny as a color and drops it beside one. */}
      <div className="flex gap-2 text-tiny">
        {b.history.map((h) => (
          <span key={h.month} className={cn("flex-1 text-center", h.month === b.month ? "font-medium text-foreground" : "text-muted-foreground")}>
            {formatMonthLabel(h.month)}
          </span>
        ))}
      </div>
      <p className="flex items-center gap-1.5 text-tiny text-muted-foreground">
        <span aria-hidden className="h-0.5 w-3 rounded-full bg-foreground/70" /> plan
      </p>
    </div>
  );
}
