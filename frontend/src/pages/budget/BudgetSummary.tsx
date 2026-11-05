import { cn, formatCurrency, moneyColor } from "@/lib/utils";
import type { BudgetData } from "@/api/types";
import { BudgetProgress } from "./BudgetProgress";
import { daysInMonth } from "./budgetMonth";

/**
 * The month in one card: spent of available, what's left, and one status
 * line — the end-of-month forecast for the current month, the outcome for a
 * past one. Income shows only once the household sets a target.
 */
export function BudgetSummary({ data }: { data: BudgetData }) {
  const available = data.actual + data.remaining;
  const percentUsed = available > 0 ? (data.actual / available) * 100 : data.actual > 0 ? 100 : 0;
  const pace = data.pace.current ? data.pace.percent_elapsed : null;

  return (
    <section className="rounded-xl border bg-card p-4 shadow-sm" aria-label="Month summary">
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-1">
        <div>
          <p className="text-xs text-muted-foreground">Spent</p>
          <p className="mt-0.5 text-2xl font-semibold tabular-nums leading-tight">
            {formatCurrency(data.actual)}
            <span className="ml-1.5 text-sm font-normal text-muted-foreground">of {formatCurrency(available)}</span>
          </p>
        </div>
        <p className={cn("text-sm font-medium tabular-nums", moneyColor(data.remaining))}>
          {data.remaining >= 0
            ? `${formatCurrency(data.remaining)} left`
            : `${formatCurrency(-data.remaining)} over`}
        </p>
      </div>

      <BudgetProgress percentUsed={percentUsed} paceElapsed={pace} className="mt-3" />

      <div className="mt-3 flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1 text-xs">
        <StatusLine data={data} />
        <span className="text-muted-foreground tabular-nums">
          {data.pace.current && <>{dayOfMonth(data.month, data.pace.percent_elapsed)}</>}
          {data.income.planned != null && (
            <>
              {data.pace.current && " · "}
              Income {formatCurrency(data.income.actual)} of {formatCurrency(data.income.planned)}
            </>
          )}
        </span>
      </div>
    </section>
  );
}

function StatusLine({ data }: { data: BudgetData }) {
  const { forecast } = data;

  if (forecast) {
    if (forecast.over_by >= 1) {
      const names = forecast.overages.map((o) => o.category_name);
      return (
        <p className="font-medium text-warning">
          Heading {formatCurrency(forecast.over_by)} over by month end
          {names.length > 0 && <span className="font-normal"> — mostly {joinNames(names)}</span>}
        </p>
      );
    }
    return (
      <p className="font-medium text-positive">
        {-forecast.over_by >= 1
          ? `On track — about ${formatCurrency(-forecast.over_by)} to spare by month end`
          : "On track to land right on budget"}
        {forecast.overages.length > 0 && (
          <span className="font-normal text-warning"> · watch {joinNames(forecast.overages.map((o) => o.category_name))}</span>
        )}
      </p>
    );
  }

  if (data.pace.percent_elapsed >= 100) {
    return data.remaining >= 0
      ? <p className="font-medium text-positive">Finished {formatCurrency(data.remaining)} under budget</p>
      : <p className="font-medium text-negative">Finished {formatCurrency(-data.remaining)} over budget</p>;
  }
  return <p className="text-muted-foreground">Planned ahead — nothing spent yet</p>;
}

function joinNames(names: string[]): string {
  if (names.length <= 1) return names.join("");
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

function dayOfMonth(month: string, percentElapsed: number): string {
  const days = daysInMonth(month);
  const day = Math.min(Math.max(Math.round((percentElapsed / 100) * days), 1), days);
  return `Day ${day} of ${days}`;
}
