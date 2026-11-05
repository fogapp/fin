import { useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { ErrorState } from "@/components/PageState";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { ChartCard, LineChart, SegmentedToggle } from "@/components/charts";
import { cn, formatCurrency } from "@/lib/utils";

type Horizon = "5" | "10" | "20" | "30";

// A deliberately simple "where does this trajectory land?" chart: current net
// worth compounded at a flat growth rate plus a flat monthly contribution.
// Defaults come from the backend (latest net-worth point + trailing-12-month
// net savings); both knobs are editable.
export function ProjectionCard() {
  const [horizon, setHorizon] = useState<Horizon>("10");
  const [growth, setGrowth] = useState("");   // "" = server default
  const [monthly, setMonthly] = useState(""); // "" = server default
  const { data, isLoading, error, refetch, isPlaceholderData } = useQuery({
    ...queries.netWorthProjection({
      years: Number(horizon),
      growth: growth || undefined,
      monthly: monthly || undefined,
    }),
    placeholderData: keepPreviousData,
  });

  return (
    <ChartCard
      title="Projection"
      subtitle={data
        ? `${formatCurrency(data.starting, true)} today, growing ${data.annual_growth_percent}%/yr with ${formatCurrency(data.monthly_contribution, true)}/mo added`
        : undefined}
      control={
        <SegmentedToggle
          label="Projection horizon"
          options={[
            { value: "5", label: "5Y" }, { value: "10", label: "10Y" },
            { value: "20", label: "20Y" }, { value: "30", label: "30Y" },
          ]}
          value={horizon}
          onChange={setHorizon}
        />
      }
    >
      {isLoading ? (
        <Skeleton className="h-56 rounded-lg" />
      ) : error || !data ? (
        <ErrorState title="Failed to load the projection" onRetry={() => refetch()} />
      ) : (
        <div className={cn("space-y-3", isPlaceholderData && "opacity-50 transition-opacity")}>
          <LineChart
            data={data.series}
            series={[{ key: "value", label: "Projected net worth" }]}
            height={220}
            area
          />
          <div className="flex flex-wrap items-end gap-4">
            <label className="flex flex-col gap-1 text-caption font-medium text-muted-foreground">
              Growth %/yr
              <Input
                type="number"
                step="0.5"
                placeholder={String(data.annual_growth_percent)}
                value={growth}
                onChange={(e) => setGrowth(e.target.value)}
                className="h-7 w-24 px-2 text-xs"
              />
            </label>
            <label className="flex flex-col gap-1 text-caption font-medium text-muted-foreground">
              Contribution $/mo
              <Input
                type="number"
                step="100"
                placeholder={String(data.monthly_contribution)}
                value={monthly}
                onChange={(e) => setMonthly(e.target.value)}
                className="h-7 w-28 px-2 text-xs"
              />
            </label>
            <p className="ml-auto text-xs text-muted-foreground">
              Lands at <span className="font-semibold text-foreground tabular-nums">
                {formatCurrency(data.series[data.series.length - 1]?.value ?? data.starting, true)}
              </span> in {data.years} years
            </p>
          </div>
        </div>
      )}
    </ChartCard>
  );
}
