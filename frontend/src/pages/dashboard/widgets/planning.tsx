/** Planning widgets: budget pace, upcoming bills, subscription costs. */
import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { EmptyChart } from "@/components/PageState";
import { currentMonth } from "@/pages/budget/budgetMonth";
import { monthLabel } from "@/lib/monthLabel";
import { formatCurrency, formatDate } from "@/lib/utils";
import {
  MeterBar, StatRow, WidgetCard, WidgetError, WidgetShell, WidgetSkeleton, type WidgetProps,
} from "../shell";

export function BudgetPaceWidget({ showEmpty }: WidgetProps) {
  const month = currentMonth();
  const { data, isLoading, isError, refetch } = useQuery(queries.budget(month));

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Budget" to="/budget" meta={monthLabel(month)}>{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const hasData = data && typeof data.planned === "number" && data.planned > 0;
  if (!hasData) {
    return showEmpty ? shell(<EmptyChart message="No budget set this month" />) : null;
  }

  const pctUsed = data.planned > 0 ? (data.actual / data.planned) * 100 : 0;
  const elapsed = data.pace?.percent_elapsed ?? null;
  const over = data.actual > data.planned;
  const aheadOfPace = elapsed != null && pctUsed > elapsed;
  const tone = over ? "negative" : aheadOfPace ? "warning" : "primary";

  return shell(
    <WidgetCard>
      <div className="flex items-baseline justify-between">
        <span className="text-lg font-semibold tabular-nums">{formatCurrency(data.actual, true)}</span>
        <span className="text-xs text-muted-foreground/70">of {formatCurrency(data.planned, true)}</span>
      </div>
      <MeterBar value={data.actual} max={data.planned} markerPct={elapsed ?? undefined} tone={tone} />
      <div className="flex items-baseline justify-between text-xs text-muted-foreground">
        <span>{Math.round(pctUsed)}% used{elapsed != null && ` · ${Math.round(elapsed)}% of month`}</span>
        <span className={over ? "text-negative" : "text-positive"}>
          {over
            ? `${formatCurrency(data.actual - data.planned, true)} over`
            : `${formatCurrency(data.remaining, true)} left`}
        </span>
      </div>
    </WidgetCard>,
  );
}

export function UpcomingBillsWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.subscriptionsUpcoming(30));

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Upcoming Bills" to="/subscriptions" meta="30 days">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const upcoming = data?.upcoming ?? [];
  if (upcoming.length === 0) {
    return showEmpty ? shell(<EmptyChart message="Nothing due in 30 days" />) : null;
  }

  const shown = upcoming.slice(0, 5);
  const total = upcoming.reduce((s, u) => s + (u.expected_amount ?? 0), 0);

  return shell(
    <WidgetCard>
      {shown.map((u) => (
        <StatRow
          key={u.occurrence_id}
          label={u.name}
          sub={formatDate(u.expected_date).replace(/, \d{4}$/, "")}
          value={u.expected_amount != null ? formatCurrency(u.expected_amount) : "—"}
        />
      ))}
      <div className="flex items-baseline justify-between border-t pt-2 text-xs text-muted-foreground">
        <span>{upcoming.length > shown.length ? `+${upcoming.length - shown.length} more · ` : ""}total due</span>
        <span className="tabular-nums font-medium text-foreground">{formatCurrency(total, true)}</span>
      </div>
    </WidgetCard>,
  );
}

export function SubscriptionsWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.subscriptions("active"));

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Subscriptions" to="/subscriptions">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const summary = data?.summary;
  if (!summary || summary.active_count === 0) {
    return showEmpty ? shell(<EmptyChart message="No active subscriptions" />) : null;
  }

  const monthTotal = summary.month_paid + summary.month_remaining;
  return shell(
    <WidgetCard>
      <StatRow label="Active" value={summary.active_count} />
      <StatRow label="Monthly" value={formatCurrency(summary.monthly_total, true)} />
      <StatRow label="Annual" value={formatCurrency(summary.annual_total, true)} />
      {monthTotal > 0 && (
        <div className="space-y-1 border-t pt-2">
          <MeterBar value={summary.month_paid} max={monthTotal} />
          <div className="flex justify-between text-xs text-muted-foreground">
            <span>{formatCurrency(summary.month_paid, true)} paid</span>
            <span>{formatCurrency(summary.month_remaining, true)} to go</span>
          </div>
        </div>
      )}
    </WidgetCard>,
  );
}
