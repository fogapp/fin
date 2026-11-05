import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { format, isToday, isYesterday } from "date-fns";
import { queries } from "@/api/queries";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { EmptyState } from "@/components/ui/empty-state";
import { SkeletonList } from "@/components/ui/skeleton";
import { Tabs } from "@/components/ui/tabs";
import { ActivityGroupRow, ActivityRow } from "./activity/ActivityRow";
import { HealthStrip } from "./activity/HealthStrip";
import { ReconciliationInbox } from "./activity/ReconciliationInbox";
import { ALL_FILTERS, TIMELINE_FILTERS } from "./activity/filters";
import type { ActivityGroup } from "@/api/types";
import { Pagination } from "@/components/ui/pagination";

// ── Activity timeline ─────────────────────────────────────────────────────────

export function Activity() {
  const [filterKey, setFilterKey] = useState("all");
  const [page, setPage] = useState(1);
  const filter = ALL_FILTERS.find((f) => f.key === filterKey) ?? ALL_FILTERS[0];

  const reconciliationRef = useRef<HTMLDivElement>(null);
  const [reconciliationHighlighted, setReconciliationHighlighted] = useState(false);

  useEffect(() => {
    if (!reconciliationHighlighted) return;
    const timer = setTimeout(() => setReconciliationHighlighted(false), 1600);
    return () => clearTimeout(timer);
  }, [reconciliationHighlighted]);

  const applyFilter = (key: string) => {
    setFilterKey(key);
    setPage(1);
  };

  const focusReconciliation = () => {
    reconciliationRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    setReconciliationHighlighted(true);
  };

  const { data, isLoading, isError, refetch } = useQuery(
    queries.activityGroups({ source: filter.source, severity: filter.severity, page })
  );

  const groups = data?.groups ?? [];
  const total = data?.meta.total ?? 0;
  const perPage = data?.meta.per_page ?? 30;
  const totalPages = Math.max(1, Math.ceil(total / perPage));
  const days = groupByDay(groups);

  return (
    <div className="flex h-full flex-col">
      <PageHeader title="Activity" level={1} />

      <div className="flex-1 overflow-y-auto p-6">
        <div className="mx-auto max-w-4xl space-y-6">
          <HealthStrip onFilter={applyFilter} onFocusReconciliation={focusReconciliation} />
          <div ref={reconciliationRef}>
            <ReconciliationInbox highlighted={reconciliationHighlighted} />
          </div>

          {/* Timeline filters */}
          <Tabs
            value={filterKey}
            onChange={applyFilter}
            size="sm"
            className="flex-wrap"
            options={TIMELINE_FILTERS.map((f) => ({ value: f.key, label: f.label }))}
          />

          {isError && <ErrorState title="Failed to load activity" onRetry={() => refetch()} />}

          {isLoading && <SkeletonList rows={8} className="space-y-2" rowClassName="h-11 rounded-xl" />}

          {!isLoading && !isError && groups.length === 0 && (
            <EmptyState
              className="py-24"
              title="No activity yet."
              description="Syncs, imports, and workflow runs will show up here as they happen."
            />
          )}

          {!isLoading && !isError && days.map(({ label, groups: dayGroups }) => (
            <section key={label} className="space-y-2">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
              <div className="space-y-2">
                {dayGroups.map((group) =>
                  group.count === 1 ? (
                    <ActivityRow key={group.lead.id} entry={group.lead} />
                  ) : (
                    <ActivityGroupRow key={group.trace_id ?? group.lead.id} group={group} />
                  )
                )}
              </div>
            </section>
          ))}

          {!isLoading && !isError && (
            <Pagination
              variant="simple"
              size="xs"
              className="pt-1"
              page={page}
              totalPages={totalPages}
              summary={`${total} groups`}
              onPageChange={setPage}
            />
          )}
        </div>
      </div>
    </div>
  );
}

/** Splits the reverse-chronological group list into contiguous day buckets
 *  (by each group's most recent activity). */
function groupByDay(groups: ActivityGroup[]) {
  const days: { label: string; groups: ActivityGroup[] }[] = [];
  for (const group of groups) {
    // Never let one malformed timestamp take down the page (stale caches
    // during deploys/hot-reloads can hand us shape mismatches).
    let date = new Date(group.last_at);
    if (Number.isNaN(date.getTime())) date = new Date(group.lead?.occurred_at ?? NaN);
    const label = Number.isNaN(date.getTime())
      ? "Earlier"
      : isToday(date) ? "Today" : isYesterday(date) ? "Yesterday" : format(date, "MMMM d, yyyy");
    const last = days[days.length - 1];
    if (last && last.label === label) last.groups.push(group);
    else days.push({ label, groups: [group] });
  }
  return days;
}
