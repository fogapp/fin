import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { SlidersHorizontal } from "lucide-react";
import { queries } from "@/api/queries";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { StatRibbon } from "@/components/StatRibbon";
import { ChartLabel } from "@/components/charts";
import { TransactionTable } from "@/components/TransactionTable";
import { formatCurrency } from "@/lib/utils";
import { STAT_LINKS } from "@/lib/statFormat";
import { WIDGET_MAP } from "./dashboard/registry";
import { useWidgetSelection } from "./dashboard/useWidgetSelection";
import { CustomizeDialog } from "./dashboard/CustomizeDialog";

export function Dashboard() {
  const { data, isLoading, error, refetch } = useQuery(queries.dashboard());
  const {
    data: transactions = [],
    isLoading: txLoading,
    isError: txError,
    refetch: refetchTx,
  } = useQuery(queries.transactions({ limit: "100" }));
  // The Net Worth sidebar widget's query, so the ribbon and the widget
  // always show the same figure (and share one cached request).
  const { data: netWorth } = useQuery(queries.netWorth("1y"));
  const { selected, isCustomized, save } = useWidgetSelection();
  const [customizeOpen, setCustomizeOpen] = useState(false);

  const hasPortfolioData =
    Object.keys(data?.portfolio_chart ?? {}).length > 0 || Object.keys(data?.allocation ?? {}).length > 0;

  if (isLoading) return <LoadingState />;
  if (error || !data) {
    // Keep the header (and its avatar menu → Settings) reachable even when
    // the dashboard can't load.
    return (
      <div className="flex flex-col">
        <PageHeader title="Dashboard" level={1} sticky />
        <ErrorState title="Failed to load dashboard" message={(error as Error)?.message} onRetry={() => refetch()} />
      </div>
    );
  }
  if (data.stats.transactions === 0) return <EmptyState />;

  const { stats, compact_stats: cs } = data;

  return (
    <div className="flex flex-col">
      <PageHeader title="Dashboard" level={1} sticky />

      <StatRibbon borderTop={false} stats={[
        { label: "MTD Spend",    value: formatCurrency(cs.spend),                 change: cs.spend_change,    invertColor: true, href: STAT_LINKS.monthlySpend },
        { label: "MTD Income",   value: formatCurrency(cs.income),                change: cs.income_change,   href: STAT_LINKS.monthlyIncome },
        { label: "CC Txns",      value: cs.cc_count.toString(),                   change: cs.cc_count_change, href: STAT_LINKS.ccTransactionCount },
        { label: "Avg Txn",      value: formatCurrency(cs.cc_avg),                change: cs.cc_avg_change,   invertColor: true, href: STAT_LINKS.ccAvgTransaction },
        ...(netWorth?.stats && netWorth.series.length > 0 ? [
          { label: "Net Worth", value: formatCurrency(netWorth.stats.net_worth, true), dividerBefore: true, href: "/net-worth" },
        ] : []),
        ...(hasPortfolioData ? [
          { label: "Portfolio",    value: formatCurrency(stats.portfolio_value, true), dividerBefore: true },
          { label: "Unrealized",   value: formatCurrency(stats.unrealized, true),   highlight: (stats.unrealized >= 0 ? "positive" : "negative") as "positive" | "negative" },
          { label: "Cost Basis",   value: formatCurrency(stats.cost_basis, true) },
          { label: "YTD Income",   value: formatCurrency(stats.income_ytd, true) },
        ] : []),
        { label: "Txns",         value: stats.transactions.toLocaleString() },
      ]} />

      <div className="space-y-6 p-4 md:p-6">
        <div className="grid gap-6 lg:grid-cols-[1fr_320px]">

          {/* Left — recent transactions */}
          <div>
            <ChartLabel>Recent Activity</ChartLabel>
            <Card>
              <CardContent className="p-0">
                {txError ? (
                  <ErrorState title="Failed to load transactions" onRetry={() => refetchTx()} />
                ) : (
                  <TransactionTable
                    transactions={transactions}
                    isLoading={txLoading}
                    columns={["date", "description", "merchant", "category", "amount"]}
                    stickyOffset={56}
                  />
                )}
              </CardContent>
            </Card>
          </div>

          {/* Right — configurable insight widgets */}
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <p className="text-xs font-medium text-muted-foreground">Insights</p>
              <Button
                variant="ghost"
                size="icon-sm"
                aria-label="Customize insights"
                onClick={() => setCustomizeOpen(true)}
              >
                <SlidersHorizontal size={14} />
              </Button>
            </div>
            {selected.map((id) => {
              const widget = WIDGET_MAP.get(id);
              if (!widget) return null;
              const Widget = widget.Component;
              return <Widget key={id} showEmpty={isCustomized} />;
            })}
            {selected.length === 0 && (
              <button
                onClick={() => setCustomizeOpen(true)}
                className="w-full rounded-xl border border-dashed p-4 text-sm text-muted-foreground transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                No insights selected — customize this column
              </button>
            )}
          </div>
        </div>
      </div>

      <CustomizeDialog
        open={customizeOpen}
        onOpenChange={setCustomizeOpen}
        selected={selected}
        onSave={save}
      />
    </div>
  );
}

// ── Recent activity panel ─────────────────────────────────────────────────────


// ── Helpers ───────────────────────────────────────────────────────────────────


function LoadingState() {
  return (
    <div className="flex flex-col">
      <div className="flex h-14 items-center border-b px-6">
        <Skeleton className="h-5 w-28" />
      </div>
      <div className="h-12 bg-muted/50 border-b animate-pulse" />
      <div className="space-y-6 p-6">
        <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
          <Skeleton className="h-96 rounded-xl" />
          <div className="space-y-4">
            {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-44 rounded-xl" />)}
          </div>
        </div>
      </div>
    </div>
  );
}

function EmptyState() {
  const navigate = useNavigate();
  // The header carries the avatar menu, the only route to Settings — a fresh
  // install lands here, so it must stay visible.
  return (
    <div className="flex h-full flex-col">
      <PageHeader title="Dashboard" level={1} sticky />
      <div className="relative isolate flex flex-1 items-center justify-center overflow-hidden p-12">
        {/* Fin watermark — fixed to viewport's bottom-right, sized to half
            the viewport width. `overflow-hidden` on the parent prevents the
            inner content from causing scroll regardless of viewport size. */}
        <img
          src="/background.png"
          alt=""
          aria-hidden
          className="pointer-events-none fixed bottom-0 right-0 -z-10 w-[50vw] opacity-[0.08]"
        />
  
        <div className="w-full max-w-lg space-y-8 text-center">
          <div>
            <p className="text-2xl font-semibold">Welcome to Fin</p>
            <p className="mt-2 text-muted-foreground">
              No transactions yet. Add data to get started.
            </p>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <button
              onClick={() => navigate("/accounts")}
              className="rounded-xl border p-5 text-left hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <p className="font-medium">Import a CSV</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Upload a checking or credit card export from your bank.
              </p>
            </button>
            <button
              onClick={() => navigate("/settings")}
              className="rounded-xl border p-5 text-left hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <p className="font-medium">Connect via Plaid</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Link your bank or credit card for automatic syncing.
              </p>
            </button>
            <button
              onClick={() => navigate("/workflows")}
              className="rounded-xl border p-5 text-left hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <p className="font-medium">Set up workflows</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Auto-assign merchants, categories and tags as transactions arrive.
              </p>
            </button>
            <button
              onClick={() => navigate("/market")}
              className="rounded-xl border p-5 text-left hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <p className="font-medium">Watch securities</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Track prices for stocks, ETFs and other instruments.
              </p>
            </button>
          </div>
          <p className="text-xs text-muted-foreground">
            Go to <strong>Accounts</strong> to create an account and import your first CSV.
          </p>
        </div>
      </div>
    </div>
  );
}
