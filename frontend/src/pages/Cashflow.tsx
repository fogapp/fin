import { useEffect, useState, type ReactNode } from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { queries } from "@/api/queries";
import { useHashParam } from "@/hooks/useHashParam";
import { cn } from "@/lib/utils";
import { usePageTimeframe } from "@/hooks/useTimeframeButtons";
import type { CashflowScopeState } from "./cashflow/ScopeFilter";
import { SectionRailNav } from "@/components/layout/SectionRailNav";
import { ErrorState } from "@/components/PageState";
import { Skeleton } from "@/components/ui/skeleton";
import { SpendingSection } from "./cashflow/SpendingSection";
import { IncomeSection } from "./cashflow/IncomeSection";
import { MoneyFlowSection } from "./cashflow/MoneyFlowSection";
import { TransfersSection } from "./cashflow/TransfersSection";
import { ActivitySection } from "./cashflow/ActivitySection";
import { Budget } from "./Budget";
import { Subscriptions } from "./Subscriptions";

const SECTIONS = [
  { id: "activity",      label: "Activity" },
  { id: "spending",      label: "Spending" },
  { id: "income",        label: "Income" },
  { id: "flow",          label: "Money Flow" },
  { id: "transfers",     label: "Transfers" },
  { id: "budget",        label: "Budget" },
  { id: "subscriptions", label: "Subscriptions" },
];

const SCOPE_KEY = "cashflow-scope";

function readScope(): CashflowScopeState {
  try {
    return JSON.parse(sessionStorage.getItem(SCOPE_KEY) ?? "{}") as CashflowScopeState;
  } catch {
    return {};
  }
}

export function Cashflow() {
  const [section, setSection] = useHashParam("section");
  const active = section ?? "activity";
  const timeframe = usePageTimeframe("cashflow", "cashflow-timeframe");
  // Account/tag scoping (and tag exclusions) shared by the analysis sections (Spending, Income,
  // Money Flow) — one pair of filters, like the timeframe.
  const [scope, setScope] = useState<CashflowScopeState>(readScope);
  useEffect(() => {
    sessionStorage.setItem(SCOPE_KEY, JSON.stringify(scope));
  }, [scope]);

  const { from, to } = timeframe;
  // Only Spending and Income consume the cashflow query — it's the heaviest
  // endpoint on the page, so don't fire it while another section is open.
  const cashflowVisible = active === "spending" || active === "income";
  const { data, isLoading, error, refetch, isPlaceholderData } = useQuery({
    ...queries.cashflow({ from, to, account_id: scope.accountId, tag_id: scope.tagId, exclude_tag_ids: scope.excludeTagIds }),
    placeholderData: keepPreviousData,
    enabled: cashflowVisible,
  });

  // Every non-cashflow section fetches its own data, so gating them on this
  // query would serialize two round-trips for no reason — they render
  // immediately instead.
  let content: ReactNode;
  if (active === "budget") {
    content = <Budget />;
  } else if (active === "subscriptions") {
    content = <Subscriptions />;
  } else if (active === "activity") {
    content = <ActivitySection />;
  } else if (active === "flow") {
    content = <MoneyFlowSection timeframe={timeframe} scope={scope} onScopeChange={setScope} />;
  } else if (active === "transfers") {
    content = <TransfersSection />;
  } else if (isLoading) {
    content = <LoadingState />;
  } else if (error || !data) {
    content = <ErrorState title="Failed to load cashflow data" onRetry={() => refetch()} />;
  } else {
    content = (
      // Hold the previous render at reduced opacity while a new range loads
      <div className={cn(isPlaceholderData && "opacity-50 transition-opacity")}>
        {active === "spending" && <SpendingSection data={data} timeframe={timeframe} scope={scope} onScopeChange={setScope} />}
        {active === "income"   && <IncomeSection data={data} timeframe={timeframe} scope={scope} onScopeChange={setScope} />}
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col md:flex-row">
      {/* Sub-nav — sidebar on desktop, horizontal tabs on mobile */}
      <SectionRailNav title="Cashflow" sections={SECTIONS} active={active} onSelect={setSection} />

      {/* Content — the page-scoped timeframe control renders inside the
          visible section's primary chart card header */}
      <div className="flex-1 overflow-y-auto pb-16 md:pb-0">
        {content}
      </div>
    </div>
  );
}

function LoadingState() {
  return (
    <div>
      <div className="h-14 border-b" />
      <Skeleton className="h-12 rounded-none border-b bg-muted/40" />
      <div className="space-y-6 p-6">
        <Skeleton className="h-48 rounded-xl" />
        <div className="grid gap-6 lg:grid-cols-[1fr_260px]">
          <Skeleton className="h-48 rounded-xl" />
          <Skeleton className="h-48 rounded-xl" />
        </div>
      </div>
    </div>
  );
}
