import { useMemo, useState } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { ArrowUpRight } from "lucide-react";
import { queries } from "@/api/queries";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { StatRibbon } from "@/components/StatRibbon";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ResponsiveTransactionView as TransactionTable } from "@/components/TransactionList";
import {
  ChartCard, ChartLabel, SankeyChart, SegmentedToggle, TimeframeSelector, transactionsHref,
  type SankeyNodeDatum, type Timeframe,
} from "@/components/charts";
import { ScopeFilter, type CashflowScopeState } from "./ScopeFilter";
import { ReportViews } from "./ReportViews";
import { expandFolded, type FoldReveal } from "./expandFolded";
import { useHashParam } from "@/hooks/useHashParam";
import { cn, formatCurrency } from "@/lib/utils";

/** "Common" mirrors the Spending page: the same flow with flagged-outlier
 *  spend excluded, so one-off transactions don't distort the everyday shape. */
type FlowSeriesMode = "all" | "common";

const FLOW_SERIES_OPTIONS: { value: FlowSeriesMode; label: string }[] = [
  { value: "all",    label: "All" },
  { value: "common", label: "Common" },
];

/** What the spend side fans out into. */
type FlowDimension = "category" | "category_group" | "merchant";

const FLOW_DIMENSION_OPTIONS: { value: FlowDimension; label: string }[] = [
  { value: "category",       label: "Category" },
  { value: "category_group", label: "Group" },
  { value: "merchant",       label: "Merchant" },
];

/** A selected sankey node with drill metadata — scopes the table below.
 *  For a category group, `id` is the joined id list (the category_ids param). */
type FlowFilter = { kind: "category" | "category_group" | "merchant"; id: string; name: string };


const NO_REVEAL: FoldReveal = { income_source: 0, category: 0 };

/** Rows each click on an "Other" node pulls out of it — long merchant tails
 *  open up gradually instead of flooding the chart. */
const REVEAL_STEP = 10;

export function MoneyFlowSection({ timeframe, scope, onScopeChange }: {
  timeframe: Timeframe;
  scope: CashflowScopeState;
  onScopeChange: (next: CashflowScopeState) => void;
}) {
  const { from, to } = timeframe;
  // Mode toggles live in the hash so a saved report (and the URL itself)
  // captures them; defaults stay out of the hash entirely.
  const [modeParam, setModeParam] = useHashParam("mode", { replace: true });
  const seriesMode: FlowSeriesMode = modeParam === "common" ? "common" : "all";
  const setSeriesMode = (m: FlowSeriesMode) => setModeParam(m === "all" ? null : m);
  const [dimParam, setDimParam] = useHashParam("dim", { replace: true });
  const dimension: FlowDimension =
    dimParam === "category_group" || dimParam === "merchant" ? dimParam : "category";
  const [reveal, setReveal] = useState<FoldReveal>(NO_REVEAL);
  const setDimension = (d: FlowDimension) => {
    setDimParam(d === "category" ? null : d);
    setReveal(NO_REVEAL);
  };
  const [filter, setFilter] = useState<FlowFilter | null>(null);
  const { data, isLoading, error, refetch, isPlaceholderData } = useQuery({
    ...queries.cashflowSankey({
      from, to,
      account_id: scope.accountId, tag_id: scope.tagId, exclude_tag_ids: scope.excludeTagIds,
      dimension: dimension === "category" ? undefined : dimension,
    }),
    placeholderData: keepPreviousData,
  });

  const showCommon = seriesMode === "common";
  const graph = data && (showCommon ? data.common : data);
  const flow = useMemo(() => graph && expandFolded(graph.nodes, graph.links, reveal), [graph, reveal]);

  if (isLoading) return (
    <div className="flex flex-col">
      <div className="h-14 border-b" />
      <Skeleton className="h-12 rounded-none border-b bg-muted/40" />
      <div className="p-6"><Skeleton className="h-80 rounded-xl" /></div>
    </div>
  );
  if (error || !data || !graph || !flow) return <ErrorState title="Failed to load money flow" onRetry={() => refetch()} />;

  const hasFlow = flow.links.length > 0;
  const expanded = reveal.income_source > 0 || reveal.category > 0;

  // Clicking a spend node (or an income source with a merchant) filters the
  // transactions table below; clicking the selected node again clears.
  // Clicking a folded "Other" node expands it instead. Hub/Savings nodes
  // carry no drill id and are ignored.
  function handleSelect(datum: SankeyNodeDatum) {
    if (datum.members?.length && (datum.kind === "income_source" || datum.kind === "category")) {
      const side = datum.kind;
      setReveal((prev) => ({ ...prev, [side]: prev[side] + REVEAL_STEP }));
      return;
    }
    const next = drillFilterFor(datum);
    if (!next) return;
    setFilter((prev) => (prev?.kind === next.kind && prev.id === next.id ? null : next));
  }

  return (
    <div className="flex flex-col">
      {/* All/Common and the timeframe live in the subheader — one pair of
          controls scoping the whole section, matching the Spending page. */}
      <PageHeader title="Money Flow" sticky>
        <ScopeFilter value={scope} onChange={onScopeChange} />
        <SegmentedToggle label="Flow transactions" options={FLOW_SERIES_OPTIONS} value={seriesMode} onChange={setSeriesMode} />
        <TimeframeSelector value={timeframe.preset} onChange={timeframe.setPreset} timeframe={timeframe} />
        <ReportViews timeframe={timeframe} scope={scope} onScopeChange={onScopeChange} />
      </PageHeader>

      <StatRibbon borderTop={false} stats={[
        { label: "Income",  value: formatCurrency(graph.totals.income, true) },
        { label: "Spend",   value: formatCurrency(graph.totals.spend, true) },
        { label: "Savings", value: formatCurrency(graph.totals.savings, true),
          highlight: graph.totals.savings >= 0 ? "positive" : "negative" },
      ]} />

      <div className={cn("space-y-6 p-6", isPlaceholderData && "opacity-50 transition-opacity")}>
        <ChartCard
          title="Money flow"
          subtitle={`Where income comes from and where it goes${showCommon ? " · excl. outliers" : ""} · click a node to see its transactions, or an Other node to expand it`}
          control={
            <div className="flex items-center gap-3">
              {expanded && (
                <button
                  type="button"
                  onClick={() => setReveal(NO_REVEAL)}
                  className="text-xs font-medium text-muted-foreground hover:text-foreground"
                >
                  Collapse
                </button>
              )}
              <SegmentedToggle label="Flow split" options={FLOW_DIMENSION_OPTIONS} value={dimension} onChange={setDimension} />
            </div>
          }
        >
          {hasFlow ? (
            <SankeyChart
              nodes={flow.nodes}
              links={flow.links}
              height={Math.max(320, flow.nodes.length * 28)}
              onSelect={handleSelect}
            />
          ) : (
            <p className="py-16 text-center text-sm text-muted-foreground">
              No cash flow in this period
            </p>
          )}
        </ChartCard>

        {filter && (
          <FlowTransactionsCard
            timeframe={timeframe}
            scope={scope}
            filter={filter}
            excludedIds={showCommon ? data.common.outlier_transaction_ids : null}
            onClear={() => setFilter(null)}
          />
        )}
      </div>
    </div>
  );
}

/** Which transaction filter a node click maps to, by drill metadata. */
function drillFilterFor(datum: SankeyNodeDatum): FlowFilter | null {
  if (datum.kind === "category") {
    if (datum.category_id) return { kind: "category", id: datum.category_id, name: datum.name };
    if (datum.category_ids?.length) return { kind: "category_group", id: datum.category_ids.join(","), name: datum.name };
    if (datum.merchant_id) return { kind: "merchant", id: datum.merchant_id, name: datum.name };
    return null;
  }
  if (datum.kind === "income_source" && datum.merchant_id) {
    return { kind: "merchant", id: datum.merchant_id, name: datum.name };
  }
  return null;
}

// The transactions endpoint clamps limit at 1,000 — enough for one category or
// merchant over the section's window; the table paginates client-side.
const TRANSACTIONS_LIMIT = 1000;

// The standard transaction table, scoped to the clicked node's category or
// merchant within the section's timeframe. In Common mode the same flagged
// rows the graph dropped are dropped here, so the table sums to the chart.
function FlowTransactionsCard({ timeframe, scope, filter, excludedIds, onClear }: {
  timeframe: Timeframe;
  scope: CashflowScopeState;
  filter: FlowFilter;
  excludedIds: string[] | null;
  onClear: () => void;
}) {
  const navigate = useNavigate();

  const queryFilters: Record<string, string> = { limit: String(TRANSACTIONS_LIMIT) };
  if (timeframe.from) queryFilters.start_date = timeframe.from;
  if (timeframe.to) queryFilters.end_date = timeframe.to;
  if (scope.accountId) queryFilters.account_id = scope.accountId;
  if (scope.tagId) queryFilters.tag_id = scope.tagId;
  if (scope.excludeTagIds?.length) queryFilters.exclude_tag_ids = scope.excludeTagIds.join(",");
  const filterParam = { category: "category_id", category_group: "category_ids", merchant: "merchant_id" }[filter.kind];
  queryFilters[filterParam] = filter.id;

  const { data: transactions, isLoading, error, refetch } = useQuery(queries.transactions(queryFilters));

  const rows = useMemo(() => {
    if (!transactions) return [];
    if (!excludedIds?.length) return transactions;
    const excluded = new Set(excludedIds);
    return transactions.filter((tx) => !excluded.has(tx.id));
  }, [transactions, excludedIds]);

  const viewAllHref = transactionsHref({
    from: timeframe.from,
    to: timeframe.to,
    accountId: scope.accountId,
    tagId: scope.tagId,
    excludeTagIds: scope.excludeTagIds,
    categoryId: filter.kind === "category" ? filter.id : undefined,
    categoryIds: filter.kind === "category_group" ? filter.id.split(",") : undefined,
    merchantId: filter.kind === "merchant" ? filter.id : undefined,
  });

  return (
    <div>
      <div className="flex items-center justify-between gap-3">
        <ChartLabel>Transactions · {filter.name}</ChartLabel>
        <div className="flex items-center gap-3 pb-2">
          <button
            type="button"
            onClick={onClear}
            className="text-xs font-medium text-muted-foreground hover:text-foreground"
          >
            Clear filter
          </button>
          <Button variant="outline" onClick={() => navigate(viewAllHref)}>
            <ArrowUpRight size={14} />
            View all in Transactions
          </Button>
        </div>
      </div>
      <Card>
        <CardContent className="p-0">
          {error ? (
            <ErrorState title="Failed to load transactions" onRetry={() => refetch()} />
          ) : (
            <TransactionTable
              transactions={rows}
              isLoading={isLoading}
              columns={["date", "description", "merchant", "account", "amount"]}
              resetKey={`${filter.kind}-${filter.id}-${timeframe.from}-${timeframe.to}`}
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
