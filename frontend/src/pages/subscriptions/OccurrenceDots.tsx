import { cn, formatDate } from "@/lib/utils";
import { occurrenceDotClass, statusLabel } from "./occurrenceStatus";
import type { RecurringOccurrence } from "@/api/types";

// Compact hit/miss evidence strip: one dot per occurrence, chronological.
export function OccurrenceDots({ occurrences }: { occurrences: RecurringOccurrence[] }) {
  if (occurrences.length === 0) return null;

  return (
    <div className="flex items-center gap-1" role="img" aria-label={`${occurrences.length} tracked charges`}>
      {occurrences.map((o) => (
        <span
          key={o.id}
          title={`${formatDate(o.expected_date)} — ${statusLabel(o)}`}
          className={cn("size-2 rounded-full", occurrenceDotClass(o.status))}
        />
      ))}
    </div>
  );
}
