/** Wealth widgets: net worth, real estate, debt, equity comp, crypto. */
import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { EmptyChart } from "@/components/PageState";
import { LineChart } from "@/components/charts";
import { formatCurrency, formatDate, moneyColor } from "@/lib/utils";
import {
  ChangeBadge, StatRow, WidgetCard, WidgetError, WidgetShell, WidgetSkeleton, type WidgetProps,
} from "../shell";

export function NetWorthWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.netWorth("1y"));
  const series = useMemo(
    () => (data?.series ?? []).map((p) => ({ date: p.date, net: p.net })),
    [data?.series],
  );

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Net Worth" to="/net-worth">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const stats = data?.stats;
  if (!stats || series.length === 0) {
    return showEmpty ? shell(<EmptyChart message="No net worth history" />) : null;
  }

  return shell(
    <div className="space-y-2">
      <div className="flex items-baseline justify-between">
        <span className="text-lg font-semibold tabular-nums">{formatCurrency(stats.net_worth, true)}</span>
        <span className="flex items-baseline gap-1 text-xs text-muted-foreground/70">
          1m <ChangeBadge pct={stats.changes?.["1m"]?.pct} />
        </span>
      </div>
      <LineChart
        data={series}
        series={[{ key: "net", label: "Net worth" }]}
        xKey="date"
        height={120}
        area
      />
    </div>,
  );
}

export function RealEstateWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.realEstateProperties());

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Real Estate" to="/net-worth">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const totals = data?.totals;
  if (!totals || totals.count === 0) {
    return showEmpty ? shell(<EmptyChart message="No properties tracked" />) : null;
  }

  return shell(
    <WidgetCard>
      <StatRow label="Value" value={formatCurrency(totals.value, true)} />
      <StatRow label="Mortgage" value={formatCurrency(-totals.mortgage, true)} valueClassName={totals.mortgage > 0 ? "text-negative" : undefined} />
      <StatRow label="Equity" value={formatCurrency(totals.equity, true)} valueClassName="text-positive" />
    </WidgetCard>,
  );
}

export function DebtWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.loans());

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Loans & Debt" to="/loans">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const active = (Array.isArray(data) ? data : []).filter((l) => l.status === "active");
  if (active.length === 0) {
    return showEmpty ? shell(<EmptyChart message="No active loans" />) : null;
  }

  const total = active.reduce((s, l) => s + l.current_balance, 0);
  const weightedRate = total > 0
    ? active.reduce((s, l) => s + l.current_balance * l.interest_rate, 0) / total
    : null;
  const top = [...active].sort((a, b) => b.current_balance - a.current_balance).slice(0, 3);

  return shell(
    <WidgetCard>
      <div className="flex items-baseline justify-between">
        <span className="text-lg font-semibold tabular-nums text-negative">{formatCurrency(total, true)}</span>
        {weightedRate != null && (
          <span className="text-xs text-muted-foreground/70">{weightedRate.toFixed(2)}% avg rate</span>
        )}
      </div>
      {top.map((l) => (
        <StatRow
          key={l.id}
          label={l.name}
          value={formatCurrency(l.current_balance, true)}
          sub={`${l.interest_rate.toFixed(2)}%`}
        />
      ))}
      {active.length > top.length && (
        <p className="text-xs text-muted-foreground/70">+{active.length - top.length} more</p>
      )}
    </WidgetCard>,
  );
}

export function EquityVestingWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.equitySummary());

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Equity Vesting" to="/equity">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const totals = data?.totals;
  const hasData = totals && (totals.vested_value > 0 || totals.unvested_value > 0 || totals.upcoming_vests?.length > 0);
  if (!hasData) {
    return showEmpty ? shell(<EmptyChart message="No equity grants" />) : null;
  }

  const next = totals.upcoming_vests?.[0];
  return shell(
    <WidgetCard>
      <StatRow label="Vested" value={formatCurrency(totals.vested_value, true)} valueClassName="text-positive" />
      <StatRow label="Unvested" value={formatCurrency(totals.unvested_value, true)} />
      {next && (
        <div className="border-t pt-2 text-xs text-muted-foreground">
          Next vest {formatDate(next.date)} · {next.company_name}
          {next.value != null && <span className="float-right tabular-nums font-medium text-foreground">{formatCurrency(next.value, true)}</span>}
        </div>
      )}
    </WidgetCard>,
  );
}

export function CryptoWidget({ showEmpty }: WidgetProps) {
  const { data, isLoading, isError, refetch } = useQuery(queries.crypto());

  if (isLoading) return <WidgetSkeleton />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title="Crypto" to="/investments">{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const summary = data?.summary;
  if (!summary || summary.total_value === 0) {
    return showEmpty ? shell(<EmptyChart message="No crypto positions" />) : null;
  }

  const top = (data.positions ?? []).slice(0, 3);
  return shell(
    <WidgetCard>
      <div className="flex items-baseline justify-between">
        <span className="text-lg font-semibold tabular-nums">{formatCurrency(summary.total_value, true)}</span>
        <span className={`text-xs tabular-nums ${moneyColor(summary.unrealized_gl)}`}>
          {formatCurrency(summary.unrealized_gl, true)}
        </span>
      </div>
      {top.map((p) => (
        <StatRow key={p.id} label={p.ticker ?? p.name ?? "—"} value={formatCurrency(p.market_value, true)} />
      ))}
    </WidgetCard>,
  );
}
