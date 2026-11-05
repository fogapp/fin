import { useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { formatDate } from "@/lib/utils";

/** RentCast-only quota section, slotted into the shared detail via the provider descriptor. */
export function RentcastUsage() {
  const { data: config } = useQuery(queries.rentcastConfiguration());
  const quota = config?.quota;
  const usedPct = quota && quota.limit > 0 ? Math.min(100, (quota.used / quota.limit) * 100) : 0;

  if (!quota) return null;
  return (
    <div className="px-8 py-5 border-b">
      <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
        This month&rsquo;s usage
      </p>
      <div className="h-2 overflow-hidden rounded-full bg-muted">
        <div className="h-full rounded-full bg-primary" style={{ width: `${usedPct}%` }} />
      </div>
      <p className="mt-2 text-sm">
        <span className="font-medium tabular-nums">{quota.used} / {quota.limit}</span>{" "}
        <span className="text-muted-foreground">
          requests used · resets {formatDate(quota.resets_on)}
        </span>
      </p>
      <p className="mt-1 text-xs text-muted-foreground">
        {config?.property_count ?? 0} propert{(config?.property_count ?? 0) === 1 ? "y" : "ies"} ·
        valued every Monday · a property costs one request, or two when its facts are refreshed
        (roughly quarterly). The sync is skipped for the week if the remaining allowance
        can&rsquo;t cover every property.
      </p>
      {config?.last_synced_at && (
        <p className="mt-1 text-xs text-muted-foreground">
          Last sync {formatDate(config.last_synced_at)}
        </p>
      )}
    </div>
  );
}
