import { useMemo } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { ArrowLeftRight } from "lucide-react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon, type StatItem } from "@/components/StatRibbon";
import { usePageTimeframe } from "@/hooks/useTimeframeButtons";
import {
  BarChart, ChartCard, ChartLabel, LineChart, TimeframeSelector,
  defaultTooltipLabel, transactionsHref,
  type TransactionsHrefParams,
} from "@/components/charts";
import { Skeleton } from "@/components/ui/skeleton";
import { KeyValueTable } from "@/components/ui/key-value-table";
import { ErrorState, EmptyChart } from "@/components/PageState";
import { queries } from "@/api/queries";
import { cn, formatDate, formatPercent } from "@/lib/utils";
import { formatStatValue, invertColorFor, statTooltipFormat, statYFormat } from "@/lib/statFormat";
import { ChangeBadge } from "./ChangeBadge";
import type { StatDetailData, StatDrill } from "@/api/types";

/** Backend drill params (snake_case) → transactionsHref params. */
function drillParams(drill: StatDrill): TransactionsHrefParams {
  const p = drill.params;
  return {
    from: p.from, to: p.to, month: p.month,
    categoryId: p.category_id, merchantId: p.merchant_id,
    tagId: p.tag_id, accountId: p.account_id, source: p.source,
  };
}

function periodLabel(data: StatDetailData, date: string): string {
  if (data.granularity !== "month") return formatDate(date);
  return new Date(`${date.slice(0, 7)}-02`).toLocaleDateString("en-US", { month: "short", year: "numeric" });
}

export function StatDetail() {
  const { key = "" } = useParams();
  const navigate = useNavigate();
  const timeframe = usePageTimeframe("stats", "stats-timeframe");

  const { data, isLoading, isError, error, refetch, isPlaceholderData } = useQuery({
    ...queries.stat(key, { from: timeframe.from, to: timeframe.to }),
    placeholderData: keepPreviousData,
  });

  const chartData = useMemo(
    () => (data?.series ?? []).map((p) => ({ date: p.date, value: p.value })),
    [data],
  );

  if (isLoading) return <LoadingState />;

  if (isError || !data) {
    return (
      <div className="flex flex-col">
        <PageHeader title="Stat" level={2} back={{ to: "/stats", label: "Back to stats" }} />
        <ErrorState
          title="Failed to load stat"
          message={(error as Error)?.message}
          onRetry={() => refetch()}
        />
      </div>
    );
  }

  const { summary } = data;
  const latest = summary.latest;
  const partial = Boolean(latest?.partial);
  const flow = data.value_type === "flow";
  const partialFlow = flow && partial;
  const monthly = data.granularity === "month";
  const drill = data.drill;

  const ribbon: StatItem[] = [
    {
      label: partialFlow ? "This month (MTD)" : "Latest",
      value: formatStatValue(latest?.value, data.unit),
      change: summary.change_pct,
      invertColor: invertColorFor(data.direction),
    },
    { label: flow ? "Prior month" : "1 month ago", value: formatStatValue(summary.previous?.value, data.unit) },
    { label: "Average", value: formatStatValue(summary.avg, data.unit) },
    { label: "Low", value: formatStatValue(summary.min?.value, data.unit) },
    { label: "High", value: formatStatValue(summary.max?.value, data.unit) },
    { label: "1M", value: formatPercent(summary.changes["1m"]), dividerBefore: true },
    { label: "3M", value: formatPercent(summary.changes["3m"]) },
    { label: "YTD", value: formatPercent(summary.changes.ytd) },
    { label: "1Y", value: formatPercent(summary.changes["1y"]) },
  ];

  const partialX = partialFlow && latest ? latest.date : undefined;
  const hasBreakdowns = Boolean(data.breakdowns?.length);

  return (
    <div className={cn("flex flex-col", isPlaceholderData && "opacity-50 transition-opacity")}>
      <PageHeader
        title={data.label}
        level={2}
        back={{ to: "/stats", label: "Back to stats" }}
        actions={drill?.route === "/transactions" ? [ {
          label: "View transactions",
          icon: ArrowLeftRight,
          onSelect: () => navigate(transactionsHref({
            ...drillParams(drill),
            from: data.range.from,
            to: data.range.to,
          })),
        } ] : []}
      />

      <StatRibbon borderTop={false} stats={ribbon} />

      <div className="p-4 md:p-6">
        <div className={cn("grid gap-6", hasBreakdowns && "lg:grid-cols-[1fr_280px]")}>
          <div className="space-y-6">
            {/* Hero */}
            <div>
              {data.description && (
                <p className="text-sm text-muted-foreground">{data.description}</p>
              )}
              <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1">
                <span className="text-3xl font-bold tabular-nums tracking-tight">
                  {formatStatValue(latest?.value, data.unit)}
                </span>
                <ChangeBadge change={summary.change_pct} direction={data.direction} size="md" />
              </div>
              {latest && (
                <p className="mt-1 text-xs text-muted-foreground">
                  As of {periodLabel(data, latest.date)}
                  {partial && monthly && " · Month in progress"}
                  {summary.pace?.projected != null && partialFlow && (
                    <> · Projected {formatStatValue(summary.pace.projected, data.unit)} at this pace</>
                  )}
                </p>
              )}
            </div>

            {/* History chart */}
            <ChartCard
              title="History"
              control={<TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />}
            >
              {chartData.length === 0 ? (
                <EmptyChart message="No history in this timeframe" />
              ) : flow ? (
                <BarChart
                  data={chartData}
                  series={[ { key: "value", label: data.label } ]}
                  xKey="date"
                  height={260}
                  diverging
                  partialX={partialX}
                  yFormat={statYFormat(data.unit)}
                  valueFormat={statTooltipFormat(data.unit)}
                  labelFormat={(l) => l === partialX ? `${defaultTooltipLabel(l)} · in progress` : defaultTooltipLabel(l)}
                  linkFor={
                    drill?.route === "/transactions" && monthly
                      ? (d) => transactionsHref({ ...drillParams(drill), month: d.x })
                      : undefined
                  }
                />
              ) : (
                <LineChart
                  data={chartData}
                  series={[ { key: "value", label: data.label } ]}
                  xKey="date"
                  height={260}
                  area
                  yFormat={statYFormat(data.unit)}
                  valueFormat={statTooltipFormat(data.unit)}
                />
              )}
            </ChartCard>
          </div>

          {/* Breakdown rail */}
          {hasBreakdowns && (
            <div className="space-y-6">
              {data.breakdowns?.map((breakdown) => (
                <div key={breakdown.label}>
                  <ChartLabel>{breakdown.label}</ChartLabel>
                  <KeyValueTable
                    mutedLabels
                    rows={breakdown.rows.map((row) => ({
                      key: row.label,
                      label: row.label,
                      value: formatStatValue(row.value, row.unit ?? data.unit),
                    }))}
                  />
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function LoadingState() {
  return (
    <div className="flex flex-col">
      <div className="flex h-14 items-center border-b px-6">
        <Skeleton className="h-5 w-48" />
      </div>
      <div className="flex h-12 items-center gap-6 border-b px-4">
        {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-6 w-20" />)}
      </div>
      <div className="space-y-6 p-4 md:p-6">
        <Skeleton className="h-10 w-56" />
        <Skeleton className="h-72 rounded-xl" />
      </div>
    </div>
  );
}
