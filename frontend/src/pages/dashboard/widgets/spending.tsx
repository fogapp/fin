/** Spending widgets: this-month cashflow, monthly spend, top categories, outliers. */
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { EmptyChart } from "@/components/PageState";
import { BarChart, transactionsHref } from "@/components/charts";
import { fillLastMonths, formatCurrency, moneyColor } from "@/lib/utils";
import {
  StatRow, WidgetCard, WidgetError, WidgetShell, WidgetSkeleton, type WidgetProps,
} from "../shell";

// The widgets only read YTD-scoped fields (summary, top categories,
// outliers), so bound the server's chart window explicitly — with no `from`,
// /cashflow computes its monthly series and outlier scan over all history.
const YTD_FROM = `${new Date().getFullYear()}-01-01`;

export function CashflowNowWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.cashflow({ from: YTD_FROM }));

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="This Month" to="/cashflow">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const s = data?.summary;
  const hasData = s && (s.mtd_income !== 0 || s.mtd_spend !== 0 || s.ytd_income !== 0 || s.ytd_spend !== 0);
  if (!hasData) {
    return showEmpty ? shell(<EmptyChart message="No cashflow yet" />) : null;
  }

  return shell(
    <WidgetCard>
      <StatRow label="Income" value={formatCurrency(s.mtd_income)} />
      <StatRow label="Spending" value={formatCurrency(-s.mtd_spend)} />
      <StatRow label="Net" value={formatCurrency(s.mtd_net)} valueClassName={moneyColor(s.mtd_net)} />
      {s.savings_rate_ytd != null && (
        <div className="border-t pt-2">
          <StatRow label="Savings rate YTD" value={`${s.savings_rate_ytd.toFixed(1)}%`} />
        </div>
      )}
    </WidgetCard>,
  );
}

/** The classic 12-month spend bars, from the dashboard payload. */
export function MonthlySpendWidget() {
  const { data, isLoading } = useQuery(queries.dashboard());
  const spendData = useMemo(
    () => fillLastMonths(data?.monthly_spend ?? {}, 12).map(({ month, amount }) => ({ month, spend: amount })),
    [data?.monthly_spend],
  );

  if (isLoading) return <WidgetSkeleton />;
  return (
    <WidgetShell title="Monthly Spend" to="/cashflow">
      <BarChart
        data={spendData}
        series={[{ key: "spend", label: "Spend" }]}
        height={140}
        linkFor={(d) => transactionsHref({ month: d.x })}
      />
    </WidgetShell>
  );
}

export function TopCategoriesWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.cashflow({ from: YTD_FROM }));

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Top Categories" to="/cashflow" meta="6 mo">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const top = (data?.top_categories ?? []).slice(0, 5);
  if (top.length === 0) {
    return showEmpty ? shell(<EmptyChart message="No categorized spending" />) : null;
  }

  return shell(
    <WidgetCard>
      {top.map((c) => (
        <StatRow key={c.id} label={c.name} value={formatCurrency(c.amount, true)} />
      ))}
    </WidgetCard>,
  );
}

export function OutliersWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.cashflow({ from: YTD_FROM }));

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Unusual Spending" to="/cashflow">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const outliers = (data?.outliers ?? []).slice(0, 3);
  if (outliers.length === 0) {
    return showEmpty ? shell(<EmptyChart message="No outliers flagged" />) : null;
  }

  return shell(
    <WidgetCard className="space-y-2.5">
      {outliers.map((o) => (
        <div key={o.transaction_id} className="text-sm">
          <div className="flex items-baseline justify-between gap-2">
            <span className="truncate">{o.description}</span>
            <span className="tabular-nums font-medium">{formatCurrency(Math.abs(o.amount), true)}</span>
          </div>
          <p className="text-xs text-muted-foreground">
            {o.category_name}
            {o.multiple != null && <span className="text-warning"> · {o.multiple.toFixed(1)}× typical</span>}
          </p>
        </div>
      ))}
    </WidgetCard>,
  );
}
