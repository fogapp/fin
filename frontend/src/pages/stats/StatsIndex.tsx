import { useQuery } from "@tanstack/react-query";
import { PageHeader } from "@/components/layout/PageHeader";
import { ChartLabel } from "@/components/charts";
import { Skeleton } from "@/components/ui/skeleton";
import { EmptyState } from "@/components/ui/empty-state";
import { ErrorState } from "@/components/PageState";
import { queries } from "@/api/queries";
import { StatCard } from "./StatCard";

export function StatsIndex() {
  const { data, isLoading, isError, error, refetch } = useQuery(queries.stats());

  return (
    <div className="flex flex-col">
      <PageHeader title="Stats" level={1} sticky />

      {isLoading && (
        <div className="grid gap-4 p-4 sm:grid-cols-2 md:p-6 xl:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-32 rounded-xl" />
          ))}
        </div>
      )}

      {isError && !isLoading && (
        <ErrorState
          title="Failed to load stats"
          message={(error as Error)?.message}
          onRetry={() => refetch()}
        />
      )}

      {data && data.stats.length === 0 && (
        <EmptyState
          title="No stats yet"
          description="Stats appear as transaction and balance history accumulates."
          className="py-16"
        />
      )}

      {data && data.stats.length > 0 && (
        <div className="space-y-8 p-4 md:p-6">
          {data.groups.map((group) => {
            const stats = data.stats.filter((s) => s.group === group.key);
            if (stats.length === 0) return null;
            return (
              <section key={group.key}>
                <ChartLabel>{group.label}</ChartLabel>
                <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                  {stats.map((stat) => <StatCard key={stat.key} stat={stat} />)}
                </div>
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}
