import { keepPreviousData, useQuery, type QueryKey, type UseQueryOptions } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { ErrorState } from "@/components/PageState";
import { TimeframeSelector, type Timeframe } from "@/components/charts";
import { formatCurrency } from "@/lib/utils";
import { SectionLoading, SectionLayout } from "./SectionLayout";
import type { InvestmentTransaction, TopSecurity } from "@/api/types";

// ── Investment flow sections ──────────────────────────────────────────────────
// Buys, Sells, and Dividends are the same section — a ribbon, a monthly bar
// chart, a cumulative line, top securities, and the transaction table — fed by
// a different query and labels. One generic body renders all three; the
// per-kind branches below hold only what differs.

export type InvestmentFlowKind = "buys" | "sells" | "dividends";

/** The fields every flow payload shares; the rest is read via typed accessors. */
interface FlowData {
  top_securities: TopSecurity[];
  by_account: Record<string, number>;
  transactions: InvestmentTransaction[];
}

function FlowSection<T extends FlowData, K extends QueryKey>({
  timeframe,
  query,
  errorTitle,
  title,
  monthly,
  cumulative,
  ribbon,
  barLabel,
  lineLabel,
  topLabel,
}: {
  timeframe: Timeframe;
  query: (range: { from?: string; to?: string }) => UseQueryOptions<T, Error, T, K>;
  errorTitle: string;
  title: string;
  monthly: (data: T) => [string, number][];
  cumulative: (data: T) => [string, number][];
  ribbon: (data: T) => Parameters<typeof SectionLayout>[0]["ribbon"];
  barLabel: string;
  lineLabel: string;
  topLabel: string;
}) {
  const { from, to } = timeframe;
  const { data, isLoading, refetch, isPlaceholderData } = useQuery({
    ...query({ from, to }),
    placeholderData: keepPreviousData,
  });

  if (isLoading) return <SectionLoading />;
  if (!data) return <ErrorState title={errorTitle} onRetry={() => refetch()} />;

  const monthlyData = monthly(data).map(([date, v]) => ({ month: date.slice(0, 7), value: v }));
  const cumulativeData = cumulative(data).map(([date, v]) => ({ date: date.slice(0, 10), value: v }));

  return (
    <SectionLayout
      title={title}
      dimmed={isPlaceholderData}
      control={<TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />}
      ribbon={ribbon(data)}
      barData={monthlyData} barKey="value" barLabel={barLabel}
      lineData={cumulativeData} lineKey="value" lineLabel={lineLabel}
      topSecurities={data.top_securities}
      topLabel={topLabel}
      byAccount={data.by_account}
      transactions={data.transactions}
    />
  );
}

export function InvestmentFlowSection({ kind, timeframe }: {
  kind: InvestmentFlowKind;
  timeframe: Timeframe;
}) {
  // The period stat covers the selected window, or the trailing 12 months
  // when the window is open-ended ("All").
  const periodLabel = timeframe.from ? timeframe.description : "Last 12mo";

  // Branches instead of a lookup table so each config keeps its payload type.
  if (kind === "buys") {
    return (
      <FlowSection
        timeframe={timeframe}
        query={queries.buys}
        errorTitle="Failed to load buys"
        title="Buys"
        monthly={(d) => d.monthly_volume}
        cumulative={(d) => d.cumulative_invested}
        ribbon={(d) => [
          { label: "All-Time Invested", value: formatCurrency(d.totals.all_time, true) },
          { label: "YTD",               value: formatCurrency(d.totals.ytd, true) },
          { label: periodLabel,         value: formatCurrency(d.totals.last_12mo, true) },
          { label: "Transactions",      value: d.totals.count.toLocaleString() },
          { label: "Avg Size",          value: formatCurrency(d.totals.avg) },
        ]}
        barLabel="Monthly Invested"
        lineLabel="Cumulative Invested"
        topLabel="Total Invested"
      />
    );
  }

  if (kind === "sells") {
    return (
      <FlowSection
        timeframe={timeframe}
        query={queries.sells}
        errorTitle="Failed to load sells"
        title="Sells"
        monthly={(d) => d.monthly_volume}
        cumulative={(d) => d.cumulative_realized}
        ribbon={(d) => [
          { label: "Total Proceeds",  value: formatCurrency(d.totals.proceeds, true) },
          { label: "YTD Proceeds",    value: formatCurrency(d.totals.proceeds_ytd, true) },
          { label: "Realized Net",    value: formatCurrency(d.totals.realized_net, true), highlight: d.totals.realized_net >= 0 ? "positive" : "negative" },
          { label: "Short-Term G/L", value: formatCurrency(d.totals.realized_short) },
          { label: "Long-Term G/L",  value: formatCurrency(d.totals.realized_long) },
          { label: "Transactions",   value: d.totals.count.toLocaleString() },
        ]}
        barLabel="Monthly Proceeds"
        lineLabel="Cumulative Realized G/L"
        topLabel="Proceeds"
      />
    );
  }

  return (
    <FlowSection
      timeframe={timeframe}
      query={queries.dividends}
      errorTitle="Failed to load dividends"
      title="Dividends"
      monthly={(d) => d.monthly_dividends}
      cumulative={(d) => d.cumulative_dividends}
      ribbon={(d) => [
        { label: "Lifetime",     value: formatCurrency(d.totals.lifetime, true) },
        { label: "YTD",          value: formatCurrency(d.totals.ytd, true) },
        { label: periodLabel,    value: formatCurrency(d.totals.last_12mo, true) },
        { label: "Transactions", value: d.totals.count.toLocaleString() },
        { label: "Avg Payment",  value: formatCurrency(d.totals.avg) },
      ]}
      barLabel="Monthly Dividends"
      lineLabel="Cumulative Dividends"
      topLabel="Total Dividends"
    />
  );
}
