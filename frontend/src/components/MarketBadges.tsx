import { cn } from "@/lib/utils";
import { instrumentClassLabel, priceSourceLabel, priceAgeDays, type StalenessPrice } from "@/lib/marketData";
import type { InstrumentClass } from "@/api/types";

export function InstrumentClassChip({ instrumentClass }: { instrumentClass: InstrumentClass }) {
  return (
    <span className="shrink-0 rounded-full bg-muted px-1.5 py-px text-micro font-medium uppercase tracking-wide text-muted-foreground">
      {instrumentClassLabel(instrumentClass)}
    </span>
  );
}

/** Price-age badge: amber past 5 days old, red at 10+, hidden when fresher —
 *  weekends and market holidays make a couple of days of EOD age normal.
 *  Title carries the provider name. Matches the backend's > 5 stale count. */
export function StalenessBadge({ price, className }: { price: StalenessPrice | null; className?: string }) {
  if (!price) return null;
  const age = priceAgeDays(price);
  if (age <= 5) return null;

  return (
    <span
      title={price.source ? `Last price from ${priceSourceLabel(price.source)}` : "Price source unknown"}
      className={cn(
        "shrink-0 rounded-full px-1.5 py-px text-micro font-semibold uppercase tracking-wide",
        age >= 10 ? "bg-negative/10 text-negative" : "bg-warning/10 text-warning",
        className,
      )}
    >
      {age}d stale
    </span>
  );
}
