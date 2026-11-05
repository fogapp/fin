/**
 * Generic sparkline widget over the Stats system. All instances share one
 * `/stats` index fetch (same query key), so adding more stat widgets costs
 * no extra requests.
 */
import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { EmptyChart } from "@/components/PageState";
import { Sparkline } from "@/components/charts/Sparkline";
import { formatStatValue, invertColorFor } from "@/lib/statFormat";
import { ChangeBadge, WidgetCard, WidgetError, WidgetShell, WidgetSkeleton, type WidgetProps } from "../shell";

export function StatSparkWidget({ statKey, title, showEmpty }: WidgetProps & {
  statKey: string;
  title: string;
}) {
  const { data, isLoading, isError, refetch } = useQuery(queries.stats());

  if (isLoading) return <WidgetSkeleton className="h-20" />;
  const shell = (children: React.ReactNode) => (
    <WidgetShell title={title} to={`/stats/${statKey}`}>{children}</WidgetShell>
  );
  if (isError) return shell(<WidgetError onRetry={() => refetch()} />);

  const stat = data?.stats?.find((s) => s.key === statKey);
  if (!stat || stat.latest?.value == null) {
    return showEmpty ? shell(<EmptyChart message="No data yet" />) : null;
  }

  return shell(
    <WidgetCard>
      <div className="flex items-baseline justify-between">
        <span className="text-lg font-semibold tabular-nums">
          {formatStatValue(stat.latest.value, stat.unit, { compact: true })}
        </span>
        <ChangeBadge pct={stat.change_pct} invert={invertColorFor(stat.direction)} />
      </div>
      <Sparkline data={stat.sparkline} height={32} />
    </WidgetCard>,
  );
}
