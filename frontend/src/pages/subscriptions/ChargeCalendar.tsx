import { useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { queries } from "@/api/queries";
import { ErrorState } from "@/components/PageState";
import { Skeleton } from "@/components/ui/skeleton";
import { cn, formatCurrency } from "@/lib/utils";
import { currentMonth, shiftMonth, daysInMonth } from "@/pages/budget/budgetMonth";
import { monthLabel } from "@/lib/monthLabel";
import { occurrenceDotClass, statusLabel } from "./occurrenceStatus";
import type { SubscriptionsCalendarOccurrence } from "@/api/types";

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const LEGEND: { status: SubscriptionsCalendarOccurrence["status"]; label: string }[] = [
  { status: "paid", label: "Paid" },
  { status: "paid_amount_changed", label: "Amount changed" },
  { status: "missed", label: "Missed" },
  { status: "upcoming", label: "Expected" },
  { status: "skipped", label: "Skipped" },
];

// Month calendar of recurring charges: every occurrence (history included)
// on its expected day, color-coded by outcome. Clicking a charge opens its
// series drawer.
export function ChargeCalendar({ onSelectSeries }: { onSelectSeries: (id: string) => void }) {
  const [month, setMonth] = useState(currentMonth());
  const { data, isLoading, error, refetch, isPlaceholderData } = useQuery({
    ...queries.subscriptionsCalendar(month),
    placeholderData: keepPreviousData,
  });

  if (isLoading) return <Skeleton className="h-72 rounded-xl" />;
  if (error || !data) return <ErrorState title="Failed to load the charge calendar" onRetry={() => refetch()} />;

  const [year, monthNumber] = month.split("-").map(Number);
  const leadingBlanks = new Date(year, monthNumber - 1, 1).getDay();
  const totalDays = daysInMonth(month);
  const today = new Date();
  const todayDay = today.getFullYear() === year && today.getMonth() === monthNumber - 1 ? today.getDate() : null;

  const byDay = new Map<number, SubscriptionsCalendarOccurrence[]>();
  for (const occ of data.occurrences) {
    const day = Number(occ.expected_date.slice(8, 10));
    byDay.set(day, [...(byDay.get(day) ?? []), occ]);
  }

  return (
    <div className={cn("rounded-xl border bg-card", isPlaceholderData && "opacity-50 transition-opacity")}>
      <div className="flex items-center justify-between border-b px-4 py-2">
        <p className="text-sm font-medium">{monthLabel(month)}</p>
        <div className="flex items-center gap-1">
          <button
            type="button"
            aria-label="Previous month"
            onClick={() => setMonth(shiftMonth(month, -1))}
            className="flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
          >
            <ChevronLeft size={14} />
          </button>
          <button
            type="button"
            aria-label="Next month"
            onClick={() => setMonth(shiftMonth(month, 1))}
            className="flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
          >
            <ChevronRight size={14} />
          </button>
        </div>
      </div>

      <div className="grid grid-cols-7 border-b text-center">
        {WEEKDAYS.map((d) => (
          <span key={d} className="py-1 text-tiny font-medium uppercase tracking-wide text-muted-foreground">{d}</span>
        ))}
      </div>

      <div className="grid grid-cols-7">
        {Array.from({ length: leadingBlanks }).map((_, i) => (
          <div key={`blank-${i}`} className="min-h-16 border-b border-r bg-muted/20 last:border-r-0" />
        ))}
        {Array.from({ length: totalDays }, (_, i) => i + 1).map((day) => {
          const occurrences = byDay.get(day) ?? [];
          return (
            <div
              key={day}
              className={cn(
                "min-h-16 space-y-0.5 border-b border-r p-1 [&:nth-child(7n)]:border-r-0",
                day === todayDay && "bg-primary/5",
              )}
            >
              <p className={cn("px-0.5 text-tiny tabular-nums", day === todayDay ? "font-semibold text-primary" : "text-muted-foreground")}>
                {day}
              </p>
              {occurrences.map((occ) => (
                <button
                  key={occ.id}
                  type="button"
                  title={`${occ.name} — ${statusLabel(occ)}`}
                  onClick={() => onSelectSeries(occ.series_id)}
                  className="flex w-full min-w-0 items-center gap-1 rounded px-0.5 py-px text-left transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary"
                >
                  <span className={cn("size-1.5 shrink-0 rounded-full", occurrenceDotClass(occ.status))} />
                  <span className="truncate text-caption">{occ.name}</span>
                  <span className="ml-auto hidden shrink-0 text-tiny tabular-nums text-muted-foreground lg:inline">
                    {formatCurrency(Math.abs(occ.amount ?? occ.expected_amount ?? 0))}
                  </span>
                </button>
              ))}
            </div>
          );
        })}
      </div>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2">
        {LEGEND.map(({ status, label }) => (
          <span key={status} className="flex items-center gap-1.5 text-caption text-muted-foreground">
            <span className={cn("size-2 rounded-full", occurrenceDotClass(status))} />
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}
