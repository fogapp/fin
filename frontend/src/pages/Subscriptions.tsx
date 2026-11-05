import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { CalendarSync, Check, ChevronDown, ChevronRight, X } from "lucide-react";
import { queries } from "@/api/queries";
import { api } from "@/api/client";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { StatRibbon } from "@/components/StatRibbon";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/toast";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import type { RecurringSeries } from "@/api/types";
import { OccurrenceDots } from "./subscriptions/OccurrenceDots";
import { ChargeCalendar } from "./subscriptions/ChargeCalendar";
import { SeriesDrawer } from "./subscriptions/SeriesDrawer";
import { SegmentedToggle } from "@/components/charts";
import { invalidate, keys } from "@/api/keys";

// ── Subscriptions ─────────────────────────────────────────────────────────────
// The subscription lifecycle page (docs/subscriptions-redesign.md §8):
//   1. Review queue — detection suggestions with their charge-history
//      evidence, accepted or dismissed one decision at a time.
//   2. Active — the accepted series, the authoritative subscription list.
//   3. Upcoming — the next two weeks of expected charges.
//   4. Inactive — lapsed series (stopped charging) awaiting end/restore.
// Suggestions come from Recurring::Detector; accepted series are kept
// current by Recurring::Matcher, never re-derived.

const CADENCE_BUCKETS = ["Monthly", "Weekly", "Biweekly", "Quarterly", "Annual", "Other"] as const;

function cadenceBucket(s: RecurringSeries): (typeof CADENCE_BUCKETS)[number] {
  if (s.granularity === "week") return s.quantity === 1 ? "Weekly" : s.quantity === 2 ? "Biweekly" : "Other";
  if (s.granularity === "year") return "Annual";
  if (s.quantity === 1) return "Monthly";
  if (s.quantity === 3) return "Quarterly";
  return "Other";
}

export function Subscriptions() {
  const qc = useQueryClient();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [showDismissed, setShowDismissed] = useState(false);
  const [upcomingView, setUpcomingView] = useState<"strip" | "calendar">("strip");

  const { data, isLoading, refetch } = useQuery(queries.subscriptions("active"));
  const { data: suggestedData } = useQuery(queries.subscriptions("suggested"));
  const { data: lapsedData } = useQuery(queries.subscriptions("lapsed"));
  const { data: dismissedData } = useQuery({ ...queries.subscriptions("dismissed"), enabled: showDismissed });
  const { data: upcomingData } = useQuery(queries.subscriptionsUpcoming(14));

  const lifecycle = useMutation({
    mutationFn: ({ id, verb }: { id: string; verb: "accept" | "dismiss" | "restore" | "end" }) =>
      api.post(`/subscriptions/${id}/${verb}`, {}),
    onSuccess: (_data, { verb }) => {
      invalidate(qc, keys.subscriptions);
      toast.success({
        accept: "Subscription accepted",
        dismiss: "Marked as not recurring",
        restore: "Subscription restored",
        end: "Subscription ended",
      }[verb]);
    },
    onError: () => toast.error("Action failed"),
  });

  if (isLoading) return <LoadingState />;
  if (!data) return <ErrorState title="Failed to load subscriptions" onRetry={() => refetch()} />;

  const { summary } = data;
  const suggested = suggestedData?.series ?? [];
  const lapsed = lapsedData?.series ?? [];
  const upcoming = upcomingData?.upcoming ?? [];

  const buckets = CADENCE_BUCKETS
    .map((bucket) => ({ bucket, items: data.series.filter((s) => cadenceBucket(s) === bucket) }))
    .filter(({ items }) => items.length > 0);

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <PageHeader title="Subscriptions" sticky />

      <StatRibbon borderTop={false} stats={[
        { label: "Monthly Total", value: formatCurrency(summary.monthly_total) },
        { label: "Annual Total", value: formatCurrency(summary.annual_total, true) },
        { label: "Paid This Month", value: formatCurrency(summary.month_paid) },
        { label: "Remaining This Month", value: formatCurrency(summary.month_remaining) },
        { label: "Active", value: summary.active_count.toString() },
      ]} />

      <div className="space-y-6 p-6">
        {suggested.length > 0 && (
          <section aria-label="Review suggestions">
            <div className="mb-2 flex items-center gap-2">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Needs Review</p>
              <Badge>{suggested.length}</Badge>
            </div>
            <div className="grid gap-3 lg:grid-cols-2">
              {suggested.map((s) => (
                <Card key={s.id}>
                  <CardContent className="flex items-center gap-4 p-4">
                    <button
                      type="button"
                      onClick={() => setSelectedId(s.id)}
                      className="min-w-0 flex-1 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-lg"
                    >
                      <div className="flex items-center gap-2">
                        <span className="truncate font-medium">{s.name}</span>
                        <ConfidenceBadge label={s.confidence_label} />
                      </div>
                      <p className="mt-0.5 text-xs text-muted-foreground">
                        {s.kind === "bill" ? "~" : ""}{formatCurrency(s.average_amount)} · {s.cadence_description}
                      </p>
                      <div className="mt-2">
                        <OccurrenceDots occurrences={s.timeline ?? []} />
                      </div>
                    </button>
                    <div className="flex shrink-0 gap-1.5">
                      <Button size="sm" onClick={() => lifecycle.mutate({ id: s.id, verb: "accept" })} disabled={lifecycle.isPending}>
                        <Check size={14} /> Accept
                      </Button>
                      <Button size="sm" variant="outline" onClick={() => lifecycle.mutate({ id: s.id, verb: "dismiss" })} disabled={lifecycle.isPending}>
                        <X size={14} /> Dismiss
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </section>
        )}

        <section aria-label="Upcoming charges">
          <div className="mb-2 flex items-center justify-between gap-3">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {upcomingView === "strip" ? "Next 14 Days" : "Charge Calendar"}
            </p>
            <SegmentedToggle
              label="Upcoming view"
              options={[{ value: "strip", label: "Next 14 days" }, { value: "calendar", label: "Calendar" }]}
              value={upcomingView}
              onChange={setUpcomingView}
            />
          </div>
          {upcomingView === "calendar" ? (
            <ChargeCalendar onSelectSeries={setSelectedId} />
          ) : upcoming.length > 0 ? (
            <div className="flex gap-3 overflow-x-auto pb-1">
              {upcoming.map((u) => (
                <button
                  key={u.occurrence_id}
                  type="button"
                  onClick={() => setSelectedId(u.series_id)}
                  className="min-w-36 shrink-0 rounded-xl border bg-card p-3 text-left transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  <p className="text-xs text-muted-foreground">{formatDate(u.expected_date)}</p>
                  <p className="mt-1 truncate text-sm font-medium">{u.name}</p>
                  <p className="text-sm tabular-nums text-muted-foreground">
                    {u.expected_amount != null ? formatCurrency(u.expected_amount) : "—"}
                  </p>
                </button>
              ))}
            </div>
          ) : (
            <p className="text-xs text-muted-foreground">No expected charges in the next 14 days.</p>
          )}
        </section>

        {buckets.map(({ bucket, items }) => (
          <section key={bucket} aria-label={`${bucket} subscriptions`}>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">{bucket}</p>
            <Card>
              <CardContent className="p-0">
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[560px] text-sm">
                    <thead>
                      <tr className="border-b text-xs text-muted-foreground">
                        <th className="px-4 py-2.5 text-left font-medium">Name</th>
                        <th className="px-4 py-2.5 text-right font-medium">Amount</th>
                        <th className="px-4 py-2.5 text-right font-medium">/ Month</th>
                        <th className="px-4 py-2.5 text-right font-medium">Last Charge</th>
                        <th className="px-4 py-2.5 text-right font-medium">Next Expected</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y">
                      {items.map((s) => (
                        <tr
                          key={s.id}
                          onClick={() => setSelectedId(s.id)}
                          className="cursor-pointer transition-colors hover:bg-muted/40"
                        >
                          <td className="px-4 py-2.5">
                            <div className="flex items-center gap-2">
                              <span className="font-medium">{s.name}</span>
                              {s.at_risk && (
                                <Badge variant="outline" className="border-warning/40 text-warning">missed payment</Badge>
                              )}
                              {s.price_changed_recently && (
                                <Badge variant="outline" className="border-warning/40 text-warning">price change</Badge>
                              )}
                            </div>
                          </td>
                          <td className="px-4 py-2.5 text-right tabular-nums">
                            {s.kind === "bill" ? "~" : ""}{formatCurrency(s.average_amount)}
                          </td>
                          <td className="px-4 py-2.5 text-right tabular-nums text-muted-foreground">{formatCurrency(s.monthly_equivalent)}</td>
                          <td className="px-4 py-2.5 text-right whitespace-nowrap text-muted-foreground">
                            {s.last_charge_date ? formatDate(s.last_charge_date) : "—"}
                          </td>
                          <td className="px-4 py-2.5 text-right whitespace-nowrap text-muted-foreground">
                            {s.next_expected_date ? formatDate(s.next_expected_date) : "—"}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>
          </section>
        ))}

        {data.series.length === 0 && suggested.length === 0 && (
          <EmptyState
            icon={CalendarSync}
            title="No subscriptions yet."
            description="Recurring charges are detected from transaction history after each sync; suggestions appear here for review."
          />
        )}

        {lapsed.length > 0 && (
          <section aria-label="Inactive subscriptions">
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Inactive</p>
            <Card>
              <CardContent className="divide-y p-0">
                {lapsed.map((s) => (
                  <div key={s.id} className="flex items-center gap-3 px-4 py-2.5">
                    <button
                      type="button"
                      onClick={() => setSelectedId(s.id)}
                      className="min-w-0 flex-1 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-lg"
                    >
                      <span className="font-medium">{s.name}</span>
                      <span className="ml-2 text-xs text-muted-foreground">
                        no charge since {s.last_charge_date ? formatDate(s.last_charge_date) : "—"}
                      </span>
                    </button>
                    <span className="text-sm tabular-nums text-muted-foreground">{formatCurrency(s.average_amount)}</span>
                    <Button size="sm" variant="outline" onClick={() => lifecycle.mutate({ id: s.id, verb: "end" })}>
                      Confirm ended
                    </Button>
                  </div>
                ))}
              </CardContent>
            </Card>
          </section>
        )}

        <section aria-label="Dismissed subscriptions">
          <button
            type="button"
            onClick={() => setShowDismissed((v) => !v)}
            className="flex items-center gap-1 text-xs font-medium uppercase tracking-wide text-muted-foreground transition-colors hover:text-foreground"
          >
            {showDismissed ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
            Dismissed
          </button>
          {showDismissed && (
            <Card className="mt-2">
              <CardContent className="divide-y p-0">
                {(dismissedData?.series ?? []).map((s) => (
                  <div key={s.id} className="flex items-center gap-3 px-4 py-2.5">
                    <span className="min-w-0 flex-1 truncate font-medium">{s.name}</span>
                    <span className="text-sm tabular-nums text-muted-foreground">{formatCurrency(s.average_amount)}</span>
                    <Button size="sm" variant="outline" onClick={() => lifecycle.mutate({ id: s.id, verb: "restore" })}>
                      Restore
                    </Button>
                  </div>
                ))}
                {dismissedData && dismissedData.series.length === 0 && (
                  <p className="px-4 py-3 text-sm text-muted-foreground">Nothing dismissed.</p>
                )}
              </CardContent>
            </Card>
          )}
        </section>
      </div>

      <SeriesDrawer id={selectedId} onClose={() => setSelectedId(null)} />
    </div>
  );
}

function ConfidenceBadge({ label }: { label: RecurringSeries["confidence_label"] }) {
  return (
    <Badge
      variant="outline"
      className={cn(
        label === "high" && "border-positive/40 text-positive",
        label === "medium" && "border-warning/40 text-warning",
        label === "low" && "text-muted-foreground",
      )}
    >
      {label}
    </Badge>
  );
}

function LoadingState() {
  return (
    <div className="flex flex-col">
      <div className="h-14 border-b" />
      <Skeleton className="h-12 rounded-none border-b bg-muted/40" />
      <div className="space-y-2 p-6">
        {Array.from({ length: 8 }).map((_, i) => <Skeleton key={i} className="h-14 rounded-xl" />)}
      </div>
    </div>
  );
}
