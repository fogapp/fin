import { useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, ArrowUpRight } from "lucide-react";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatRibbon } from "@/components/StatRibbon";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import {
  ChartCard, SegmentedToggle, TimeframeSelector,
  transactionsHref, useChartTheme, assignSeriesColors,
  type Timeframe,
} from "@/components/charts";
import {
  SpendChartCard, useSpendChartControls, bandNames, SPEND_SERIES_OPTIONS,
} from "@/components/spend-chart";
import { ScopeFilter, type CashflowScopeState } from "./ScopeFilter";
import { ReportViews } from "./ReportViews";
import { queries } from "@/api/queries";
import { amountColor } from "@/lib/transactions";
import { cn, formatCurrency, formatDate, fillMonthsFrom } from "@/lib/utils";
import type { CashflowData, SpendingOutlier, SpendTotal } from "@/api/types";

/** A selected By Category / By Merchant row, used to filter the transactions list below. */
type SpendFilter = { kind: "category" | "merchant"; id: string; name: string };

export function SpendingSection({ data, timeframe, scope, onScopeChange }: {
  data: CashflowData;
  timeframe: Timeframe;
  scope: CashflowScopeState;
  onScopeChange: (next: CashflowScopeState) => void;
}) {
  const theme = useChartTheme();
  const {
    summary: s, card_payments, payment_suspects,
    monthly_spend, monthly_spend_common,
    top_categories, top_categories_common, top_merchants, top_merchants_common, outliers,
  } = data;
  // Mode toggles live in the hash so a saved report (and the URL itself)
  // captures them; defaults stay out of the hash entirely.
  const controls = useSpendChartControls({ hashPersisted: true });
  const { seriesMode, dimension } = controls;
  const [filter, setFilter] = useState<SpendFilter | null>(null);

  // "Both" only makes sense on the chart, where two lines can be compared
  // over time — everywhere else on the page a stat is a single number, so
  // "outlier" and "both" both mean "as it happened" and only "common" filters.
  const showCommon = seriesMode === "common";
  const periodLabel = timeframe.description + (showCommon ? " · excl. outliers" : "");

  const spendByMonth = fillMonthsFrom(showCommon ? monthly_spend_common : monthly_spend, timeframe.from);

  // The chart's breakdown query, subscribed here too (same key — one fetch)
  // because the page's color maps need the band names below.
  const breakdownQuery = useQuery({
    ...queries.cashflowSpendBreakdown({
      from: timeframe.from, to: timeframe.to,
      account_id: scope.accountId, tag_id: scope.tagId, exclude_tag_ids: scope.excludeTagIds,
    }),
    enabled: dimension !== "none",
  });

  // ONE entity→color assignment per list, anchored to the UNION of the total
  // and common sets (excluding outliers can shrink a big spender's total
  // enough that a merchant absent from the unfiltered top-8 appears in the
  // common one) so every row that can ever render has a real color instead
  // of silently falling through to `colors.get(name) ?? undefined`. The
  // chart's bands join that union too: they're ranked over the chart's window
  // rather than the panels', so on "All time" the two sets can diverge.
  const categoryColors = useMemo(
    () => assignSeriesColors(
      unionNames(top_categories, top_categories_common, bandNames(breakdownQuery.data, "category")), theme,
    ),
    [top_categories, top_categories_common, breakdownQuery.data, theme],
  );
  const merchantColors = useMemo(
    () => assignSeriesColors(
      unionNames(top_merchants, top_merchants_common, bandNames(breakdownQuery.data, "merchant")), theme,
    ),
    [top_merchants, top_merchants_common, breakdownQuery.data, theme],
  );
  const chartColors = useMemo(
    () => ({ category: categoryColors, merchant: merchantColors }),
    [categoryColors, merchantColors],
  );

  const totals = useMemo(
    () => ({ spend: monthly_spend, common: monthly_spend_common }),
    [monthly_spend, monthly_spend_common],
  );

  const avgMonthlySpend = spendByMonth.reduce((sum, d) => sum + d.amount, 0) / Math.max(spendByMonth.length, 1);
  const mtdSpend = showCommon ? s.mtd_spend_common : s.mtd_spend;
  const lmoSpend = showCommon ? s.lmo_spend_common : s.lmo_spend;
  const ytdSpend = showCommon ? s.ytd_spend_common : s.ytd_spend;
  const mtdChange = lmoSpend > 0 ? ((mtdSpend - lmoSpend) / lmoSpend) * 100 : null;

  function toggleFilter(next: SpendFilter) {
    setFilter((prev) => (prev?.kind === next.kind && prev.id === next.id ? null : next));
  }

  return (
    <div className="flex flex-col">
      {/* Common/Outlier/Both and the timeframe live in the subheader — one
          pair of controls scoping the whole page, not just the chart. */}
      <PageHeader title="Spending" sticky>
        <ScopeFilter value={scope} onChange={onScopeChange} />
        <SegmentedToggle label="Spend series" options={SPEND_SERIES_OPTIONS} value={seriesMode} onChange={controls.setSeriesMode} />
        <TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />
        <ReportViews timeframe={timeframe} scope={scope} onScopeChange={onScopeChange} />
      </PageHeader>

      <StatRibbon borderTop={false} stats={[
        { label: "MTD",         value: formatCurrency(mtdSpend),        change: mtdChange, invertColor: true },
        { label: "Last Month",  value: formatCurrency(lmoSpend) },
        { label: "YTD",         value: formatCurrency(ytdSpend, true),  dividerBefore: true },
        { label: "Avg / Month", value: formatCurrency(avgMonthlySpend) },
        { label: "Card payments · MTD", value: formatCurrency(card_payments?.mtd ?? 0), dividerBefore: true },
      ]} />

      <div className="space-y-6 p-6">
        {/* Data-quality chip: payment-shaped debits still counted in spend.
            Exclusion is structural now — anything unlinked is visible here
            instead of silently filtered by description. */}
        {payment_suspects > 0 && (
          <Link
            to="/cashflow#section=transfers"
            className="flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/8 px-3 py-2 text-xs text-primary hover:bg-primary/15 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          >
            <AlertCircle size={13} className="shrink-0" />
            {payment_suspects} suspected card/loan payment{payment_suspects === 1 ? "" : "s"} still counted in
            spending — review and link them as payments.
          </Link>
        )}
        {/* The chart itself: series/timeframe controls stay in the page
            header above (they scope the stats and panels too), so the card
            only carries the split + scale toggles. Totals come preloaded
            from the page's cashflow payload. */}
        <SpendChartCard
          scope={{ accountId: scope.accountId, tagId: scope.tagId, excludeTagIds: scope.excludeTagIds }}
          timeframe={timeframe}
          controls={controls}
          totals={totals}
          colors={chartColors}
        />

        <div className="grid gap-6 lg:grid-cols-3">
          <RankedBars
            title="By Category"
            subtitle={periodLabel}
            rows={showCommon ? top_categories_common : top_categories}
            colors={categoryColors}
            emptyLabel={showCommon ? "No common spending in this category" : "No categorized spending yet"}
            kind="category"
            selected={filter}
            onSelect={toggleFilter}
          />
          <RankedBars
            title="By Merchant"
            subtitle={periodLabel}
            rows={showCommon ? top_merchants_common : top_merchants}
            colors={merchantColors}
            emptyLabel={showCommon ? "No common spending at this merchant" : "No merchant spending yet"}
            kind="merchant"
            selected={filter}
            onSelect={toggleFilter}
          />
          <OutliersCard outliers={outliers} colors={categoryColors} neutral={theme.neutral} subtitle={timeframe.description} />
        </div>

        <TransactionsListCard timeframe={timeframe} scope={scope} filter={filter} onClearFilter={() => setFilter(null)} />
      </div>
    </div>
  );
}

/** First-appearance order across every list — the common list can surface a
 *  row absent from the unfiltered top-8 once its biggest transactions drop out. */
function unionNames(...lists: readonly { name: string }[][]): string[] {
  return Array.from(new Set(lists.flat().map((r) => r.name)));
}

// Ranked bar list — label row (dot + name + amount) with the proportional
// fill bar and an avg/largest subline below, so the name gets the card's
// full width instead of fighting a fixed-width column for space. Rows
// arrive pre-sorted desc from the backend; fill width is relative to the
// list's own max so the largest row always reads as a full bar. Clicking a
// row filters the transactions list below to that category/merchant.
function RankedBars({ title, subtitle, rows, colors, emptyLabel, kind, selected, onSelect }: {
  title: string;
  subtitle?: string;
  rows: SpendTotal[];
  colors: Map<string, string>;
  emptyLabel: string;
  kind: SpendFilter["kind"];
  selected: SpendFilter | null;
  onSelect: (filter: SpendFilter) => void;
}) {
  const max = Math.max(...rows.map((r) => r.amount), 1);

  return (
    <ChartCard title={title} subtitle={subtitle}>
      {rows.length === 0 ? (
        <EmptyState title={emptyLabel} className="py-8" />
      ) : (
        <div className="space-y-1">
          {rows.map((row) => {
            const isSelected = selected?.kind === kind && selected.id === row.id;
            return (
              <button
                key={row.id}
                type="button"
                onClick={() => onSelect({ kind, id: row.id, name: row.name })}
                className={cn(
                  "block w-full space-y-1 rounded-lg px-1.5 py-1.5 text-left transition-colors hover:bg-accent/50",
                  isSelected && "bg-accent ring-1 ring-inset ring-primary/40",
                )}
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="flex min-w-0 items-center gap-2">
                    <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: colors.get(row.name) }} />
                    <span className="truncate text-xs" title={row.name}>{row.name}</span>
                  </span>
                  <span className="shrink-0 text-xs font-medium tabular-nums">{formatCurrency(row.amount)}</span>
                </div>
                <span className="block h-2 w-full overflow-hidden rounded-full bg-muted">
                  <span
                    className="block h-full rounded-full"
                    style={{ width: `${(row.amount / max) * 100}%`, background: colors.get(row.name) }}
                  />
                </span>
                <p className="text-caption text-muted-foreground">
                  {formatCurrency(row.avg_monthly)}/mo avg · {formatCurrency(row.largest)} largest
                </p>
              </button>
            );
          })}
        </div>
      )}
    </ChartCard>
  );
}

// Transactions that cleared their own category's statistical fence — see
// Api::Render::Cashflow#outliers. Read-only for now: these are suggestions,
// not yet a persisted "exclude from usual spend" decision.
function OutliersCard({ outliers, colors, neutral, subtitle }: {
  outliers: SpendingOutlier[];
  colors: Map<string, string>;
  neutral: string;
  subtitle: string;
}) {
  const navigate = useNavigate();

  return (
    <ChartCard title="Outliers" subtitle={subtitle} bodyClassName="p-0">
      {outliers.length === 0 ? (
        <EmptyState title="Nothing unusual" description="No transactions stood out from their category's typical spending." className="py-8" />
      ) : (
        <ul className="divide-y">
          {outliers.map((o) => (
            <li key={o.transaction_id}>
              <button
                onClick={() => navigate(`/transactions/${o.transaction_id}`)}
                className="flex w-full items-center gap-2.5 px-3 py-2.5 text-left transition-colors hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
              >
                <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: colors.get(o.category_name) ?? neutral }} />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-xs font-medium">{o.description}</p>
                  <p className="truncate text-caption text-muted-foreground">
                    {o.category_name} · {formatDate(o.transaction_date)}
                    {o.multiple != null && <span className="text-warning"> · {o.multiple}× typical</span>}
                  </p>
                </div>
                <span className="shrink-0 text-xs font-medium tabular-nums">{formatCurrency(o.amount)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </ChartCard>
  );
}

const TRANSACTIONS_LIMIT = 25;

// Timeframe-scoped transaction list below the category/merchant/outlier row.
// Clicking a By Category or By Merchant row narrows this to that selection;
// it stays a lightweight read-only list (not the full TransactionTable,
// which owns its own filter/sort state) with a footer through to the real thing.
function TransactionsListCard({ timeframe, scope, filter, onClearFilter }: {
  timeframe: Timeframe;
  scope: CashflowScopeState;
  filter: SpendFilter | null;
  onClearFilter: () => void;
}) {
  const navigate = useNavigate();

  const queryFilters: Record<string, string> = { limit: String(TRANSACTIONS_LIMIT) };
  if (timeframe.from) queryFilters.start_date = timeframe.from;
  if (timeframe.to) queryFilters.end_date = timeframe.to;
  if (scope.accountId) queryFilters.account_id = scope.accountId;
  if (scope.tagId) queryFilters.tag_id = scope.tagId;
  if (scope.excludeTagIds?.length) queryFilters.exclude_tag_ids = scope.excludeTagIds.join(",");
  if (filter?.kind === "category") queryFilters.category_id = filter.id;
  if (filter?.kind === "merchant") queryFilters.merchant_id = filter.id;

  const { data: transactions, isLoading } = useQuery(queries.transactions(queryFilters));

  const viewAllHref = transactionsHref({
    from: timeframe.from,
    to: timeframe.to,
    accountId: scope.accountId,
    tagId: scope.tagId,
    excludeTagIds: scope.excludeTagIds,
    categoryId: filter?.kind === "category" ? filter.id : undefined,
    merchantId: filter?.kind === "merchant" ? filter.id : undefined,
  });

  return (
    <ChartCard
      title="Transactions"
      subtitle={filter ? `Filtered by ${filter.name}` : undefined}
      control={filter && (
        <button
          type="button"
          onClick={onClearFilter}
          className="text-xs font-medium text-muted-foreground hover:text-foreground"
        >
          Clear filter
        </button>
      )}
      bodyClassName="p-0"
    >
      {isLoading ? (
        <div className="space-y-2 p-4">
          {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-10 rounded-lg" />)}
        </div>
      ) : !transactions || transactions.length === 0 ? (
        <EmptyState
          title="No transactions"
          description={filter ? `No transactions for ${filter.name} in this timeframe.` : "No transactions in this timeframe."}
          className="py-10"
        />
      ) : (
        <>
          <ul className="divide-y">
            {transactions.map((tx) => (
              <li key={tx.id}>
                <button
                  onClick={() => navigate(`/transactions/${tx.id}`)}
                  className="flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary"
                >
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm">{tx.merchant_name ?? tx.description}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      {formatDate(tx.transaction_date)}
                      {tx.category_name ? ` · ${tx.category_name}` : ""}
                      {tx.account_name ? ` · ${tx.account_name}` : ""}
                    </p>
                  </div>
                  <span className={cn("shrink-0 tabular-nums text-sm", amountColor(tx))}>{formatCurrency(tx.amount)}</span>
                </button>
              </li>
            ))}
          </ul>
          <div className="border-t p-3">
            <Button variant="outline" className="w-full" onClick={() => navigate(viewAllHref)}>
              <ArrowUpRight size={14} />
              View all in Transactions
            </Button>
          </div>
        </>
      )}
    </ChartCard>
  );
}
