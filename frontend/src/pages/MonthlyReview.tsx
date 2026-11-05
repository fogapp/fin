import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useSearchParams, useNavigate } from "react-router-dom";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { queries } from "@/api/queries";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon } from "@/components/StatRibbon";
import { ErrorState } from "@/components/PageState";
import { ChartCard } from "@/components/charts";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import { currentMonth, shiftMonth } from "@/pages/budget/budgetMonth";
import { monthLabel } from "@/lib/monthLabel";
import type { ReviewRankedRow } from "@/api/types";

/** Latest closed month — reviews are always about finished months. */
function latestClosedMonth(): string {
  return shiftMonth(currentMonth(), -1);
}

export function MonthlyReview() {
  const [searchParams, setSearchParams] = useSearchParams();
  const month = searchParams.get("month") ?? latestClosedMonth();
  const navigate = useNavigate();

  const { data, isLoading, error, refetch, isPlaceholderData } = useQuery({
    ...queries.review(month),
    placeholderData: keepPreviousData,
  });

  function setMonth(next: string) {
    setSearchParams({ month: next }, { replace: true });
  }

  const atLatest = month >= latestClosedMonth();

  return (
    <div className="flex h-full flex-col overflow-hidden">
      <PageHeader title={`Review · ${monthLabel(month)}`} level={1} sticky>
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
            disabled={atLatest}
            onClick={() => setMonth(shiftMonth(month, 1))}
            className="flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground disabled:opacity-40"
          >
            <ChevronRight size={14} />
          </button>
        </div>
      </PageHeader>

      <div className="flex-1 overflow-y-auto pb-16 md:pb-0">
        {isLoading ? (
          <div className="space-y-6 p-6">
            <Skeleton className="h-12 rounded-xl" />
            <div className="grid gap-6 lg:grid-cols-3">
              {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-48 rounded-xl" />)}
            </div>
          </div>
        ) : error || !data ? (
          <ErrorState title="Failed to load the review" onRetry={() => refetch()} />
        ) : (
          <div className={cn(isPlaceholderData && "opacity-50 transition-opacity")}>
            <StatRibbon borderTop={false} stats={[
              { label: "Income", value: formatCurrency(data.cashflow.income, true),
                change: pctChange(data.cashflow.income, data.cashflow.prev_income) },
              { label: "Spend", value: formatCurrency(data.cashflow.spend, true),
                change: pctChange(data.cashflow.spend, data.cashflow.prev_spend), invertColor: true },
              { label: "Net", value: formatCurrency(data.cashflow.net, true),
                highlight: data.cashflow.net >= 0 ? "positive" : "negative" },
              { label: "Savings Rate",
                value: data.cashflow.savings_rate != null ? `${data.cashflow.savings_rate.toFixed(1)}%` : "—",
                dividerBefore: true },
              ...(data.net_worth ? [{
                label: "Net Worth",
                value: formatCurrency(data.net_worth.ending, true),
                change: data.net_worth.starting ? pctChange(data.net_worth.ending, data.net_worth.starting) : null,
              }] : []),
            ]} />

            <div className="grid gap-6 p-6 lg:grid-cols-3">
              <RankedCard title="Top categories" rows={data.top_categories} emptyLabel="No categorized spending" />
              <RankedCard title="Top merchants" rows={data.top_merchants} emptyLabel="No merchant spending" />

              <ChartCard title="Largest transactions" bodyClassName="p-0">
                {data.largest_transactions.length === 0 ? (
                  <EmptyState title="No spending this month" className="py-8" />
                ) : (
                  <ul className="divide-y">
                    {data.largest_transactions.map((t) => (
                      <li key={t.id}>
                        <button
                          onClick={() => navigate(`/transactions/${t.id}`)}
                          className="flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
                        >
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-sm">{t.description}</p>
                            <p className="truncate text-xs text-muted-foreground">
                              {formatDate(t.transaction_date)}
                              {t.category_name ? ` · ${t.category_name}` : ""}
                            </p>
                          </div>
                          <span className="shrink-0 text-sm tabular-nums">{formatCurrency(t.amount)}</span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </ChartCard>

              <ChartCard title="Budget outcome">
                <dl className="space-y-2 text-sm">
                  <Row label="Planned" value={formatCurrency(data.budget.planned)} />
                  <Row label="Actual" value={formatCurrency(data.budget.actual)} />
                  <Row
                    label={data.budget.remaining >= 0 ? "Left over" : "Over budget"}
                    value={formatCurrency(Math.abs(data.budget.remaining))}
                    tone={data.budget.remaining >= 0 ? "positive" : "negative"}
                  />
                </dl>
              </ChartCard>

              <ChartCard title="Subscriptions">
                <dl className="space-y-2 text-sm">
                  <Row label="Charges paid" value={String(data.subscriptions.paid_count)} />
                  <Row label="Total" value={formatCurrency(data.subscriptions.paid_total)} />
                </dl>
              </ChartCard>

              {data.net_worth && (
                <ChartCard title="Net worth">
                  <dl className="space-y-2 text-sm">
                    <Row label="End of month" value={formatCurrency(data.net_worth.ending, true)} />
                    {data.net_worth.starting != null && (
                      <Row label="Start of month" value={formatCurrency(data.net_worth.starting, true)} />
                    )}
                    {data.net_worth.change != null && (
                      <Row
                        label="Change"
                        value={formatCurrency(data.net_worth.change, true)}
                        tone={data.net_worth.change >= 0 ? "positive" : "negative"}
                      />
                    )}
                  </dl>
                </ChartCard>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function pctChange(current: number, previous: number): number | null {
  return previous > 0 ? ((current - previous) / previous) * 100 : null;
}

function Row({ label, value, tone }: { label: string; value: string; tone?: "positive" | "negative" }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className={cn("tabular-nums font-medium", tone === "positive" && "text-positive", tone === "negative" && "text-negative")}>
        {value}
      </dd>
    </div>
  );
}

function RankedCard({ title, rows, emptyLabel }: { title: string; rows: ReviewRankedRow[]; emptyLabel: string }) {
  const max = Math.max(...rows.map((r) => r.amount), 1);
  return (
    <ChartCard title={title}>
      {rows.length === 0 ? (
        <EmptyState title={emptyLabel} className="py-8" />
      ) : (
        <div className="space-y-2">
          {rows.map((row) => (
            <div key={row.id} className="space-y-1">
              <div className="flex items-center justify-between gap-2 text-xs">
                <span className="truncate">{row.name}</span>
                <span className="shrink-0 font-medium tabular-nums">{formatCurrency(row.amount)}</span>
              </div>
              <span className="block h-2 w-full overflow-hidden rounded-full bg-muted">
                <span className="block h-full rounded-full bg-primary/60" style={{ width: `${(row.amount / max) * 100}%` }} />
              </span>
            </div>
          ))}
        </div>
      )}
    </ChartCard>
  );
}
