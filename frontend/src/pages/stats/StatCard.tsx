import { Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Sparkline } from "@/components/charts";
import { formatStatValue } from "@/lib/statFormat";
import { ChangeBadge } from "./ChangeBadge";
import type { StatSummary } from "@/api/types";

export function StatCard({ stat }: { stat: StatSummary }) {
  const partial = Boolean(stat.latest?.partial) && stat.value_type === "flow";

  return (
    <Link
      to={`/stats/${stat.key}`}
      className="block rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <Card className="h-full p-4 transition-colors hover:bg-accent/40">
        <p className="text-xs font-medium text-muted-foreground">{stat.label}</p>
        <div className="mt-1 flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <span className="text-xl font-semibold tabular-nums">
            {formatStatValue(stat.latest?.value, stat.unit)}
          </span>
          {partial && (
            <span className="rounded-full bg-muted px-1.5 py-0.5 text-tiny font-medium text-muted-foreground">
              MTD
            </span>
          )}
          <ChangeBadge change={stat.change_pct} direction={stat.direction} />
        </div>
        <Sparkline data={stat.sparkline} height={36} className="mt-3" />
      </Card>
    </Link>
  );
}
