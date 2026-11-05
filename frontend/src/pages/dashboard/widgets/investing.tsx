/** Investing widgets: portfolio value, allocation, investment income, TWR/XIRR, market pulse. */
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { EmptyChart } from "@/components/PageState";
import { BarChart, LineChart, PieChart } from "@/components/charts";
import { cn, fillLastMonths, formatCurrency, formatPercent } from "@/lib/utils";
import {
  StatRow, WidgetCard, WidgetError, WidgetShell, WidgetSkeleton, type WidgetProps,
} from "../shell";

export function PortfolioValueWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading } = useQuery(queries.dashboard());
  const points = useMemo(
    () => Object.entries(data?.portfolio_chart ?? {}).map(([date, value]) => ({ date, value })),
    [data?.portfolio_chart],
  );

  if (isLoading) return <WidgetSkeleton />;
  if (points.length === 0) {
    return showEmpty ? (
      <WidgetShell title="Portfolio Value" to="/investments"><EmptyChart message="No portfolio history" /></WidgetShell>
    ) : null;
  }

  return (
    <WidgetShell title="Portfolio Value" to="/investments">
      <LineChart data={points} series={[{ key: "value", label: "Portfolio" }]} xKey="date" height={160} area />
    </WidgetShell>
  );
}

export function AllocationWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading } = useQuery(queries.dashboard());
  const slices = useMemo(
    () => Object.entries(data?.allocation ?? {}).map(([name, value]) => ({ name, value })),
    [data?.allocation],
  );

  if (isLoading) return <WidgetSkeleton />;
  if (slices.length === 0) {
    return showEmpty ? (
      <WidgetShell title="Allocation" to="/investments"><EmptyChart message="No position snapshots" /></WidgetShell>
    ) : null;
  }

  return (
    <WidgetShell title="Allocation" to="/investments">
      <PieChart data={slices} height={180} />
    </WidgetShell>
  );
}

export function MonthlyIncomeWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading } = useQuery(queries.dashboard());
  const incomeData = useMemo(
    () => fillLastMonths(data?.income_series ?? {}, 12).map(({ month, amount }) => ({ month, income: amount })),
    [data?.income_series],
  );

  if (isLoading) return <WidgetSkeleton />;
  if (!incomeData.some((d) => d.income > 0)) {
    return showEmpty ? (
      <WidgetShell title="Investment Income" to="/investments"><EmptyChart message="No investment income" /></WidgetShell>
    ) : null;
  }

  return (
    <WidgetShell title="Investment Income" to="/investments">
      <BarChart data={incomeData} series={[{ key: "income", label: "Income" }]} height={140} />
    </WidgetShell>
  );
}

export function PerformanceWidget({ showEmpty }: WidgetProps) {
  const ytdFrom = `${new Date().getFullYear()}-01-01`;
  const { data, isLoading, isError, refetch } = useQuery(queries.portfolioPerformance(ytdFrom));

  if (isLoading) return <WidgetSkeleton className="h-20" />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Performance" to="/investments" meta="YTD">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const hasData = data && (data.twr_pct != null || data.xirr_pct != null);
  if (!hasData) {
    return showEmpty ? shell(<EmptyChart message="No performance history" />) : null;
  }

  const cells: { label: string; value: number | null }[] = [
    { label: "TWR", value: data.twr_pct },
    { label: "Annualized", value: data.twr_annualized_pct },
    { label: "XIRR", value: data.xirr_pct },
  ];

  return shell(
    <WidgetCard className="grid grid-cols-3 gap-2 space-y-0">
      {cells.map((c) => (
        <div key={c.label}>
          <p className="text-xs text-muted-foreground">{c.label}</p>
          <p className={cn(
            "tabular-nums font-medium",
            c.value != null && (c.value >= 0 ? "text-positive" : "text-negative"),
          )}>
            {c.value != null ? formatPercent(c.value) : "—"}
          </p>
        </div>
      ))}
    </WidgetCard>,
  );
}

export function MarketPulseWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.marketSummary());

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Markets" to="/market">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const indices = data?.indices ?? [];
  const gainer = data?.movers?.gainers?.[0];
  const loser = data?.movers?.losers?.[0];
  if (indices.length === 0 && !gainer && !loser) {
    return showEmpty ? shell(<EmptyChart message="No market data" />) : null;
  }

  return shell(
    <WidgetCard>
      {indices.slice(0, 4).map((ix) => (
        <StatRow
          key={ix.symbol}
          label={ix.label}
          sub={ix.close != null ? formatCurrency(ix.close, true) : undefined}
          value={ix.day_change_pct != null ? formatPercent(ix.day_change_pct) : "—"}
          valueClassName={ix.day_change_pct != null ? (ix.day_change_pct >= 0 ? "text-positive" : "text-negative") : undefined}
        />
      ))}
      {(gainer || loser) && (
        <div className="space-y-2 border-t pt-2">
          {gainer && (
            <StatRow label={gainer.display_name} value={formatPercent(gainer.day_change_pct)} valueClassName="text-positive" />
          )}
          {loser && (
            <StatRow label={loser.display_name} value={formatPercent(loser.day_change_pct)} valueClassName="text-negative" />
          )}
        </div>
      )}
    </WidgetCard>,
  );
}
