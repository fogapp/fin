import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Pencil, Sparkles } from "lucide-react";
import { queries } from "@/api/queries";
import { mutations } from "@/api/mutations";
import type { BudgetData, BudgetLine, BudgetLineMode } from "@/api/types";
import { useHashParam } from "@/hooks/useHashParam";
import { cn } from "@/lib/utils";
import { transactionsHref } from "@/components/charts";
import { PageHeader } from "@/components/layout/PageHeader";
import { ErrorState } from "@/components/PageState";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/toast";
import { SegmentedToggle } from "@/components/charts";
import { currentMonth, shiftMonth } from "./budget/budgetMonth";
import { monthLabel } from "@/lib/monthLabel";
import { BudgetCalendarView } from "./budget/BudgetCalendarView";
import { BudgetSummary } from "./budget/BudgetSummary";
import { BudgetList } from "./budget/BudgetList";
import { BudgetPlanEditor, type LineChange } from "./budget/BudgetPlanEditor";
import { BudgetLineDrawer } from "./budget/BudgetLineDrawer";
import { invalidate, keys } from "@/api/keys";

/** True once the household has budgeted anything in force this month. */
function hasPlan(data: BudgetData): boolean {
  return data.lines.length > 0 || data.yearly.lines.length > 0 || data.everything_else.planned != null;
}

export function Budget() {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [rawMonth, setMonth] = useHashParam("month");
  const month = rawMonth ?? currentMonth();
  const [drawerCategoryId, setDrawerCategoryId] = useHashParam("line");
  // Month detail vs the year-at-a-glance calendar grid.
  const [rawView, setView] = useHashParam("view", { replace: true });
  const view: "month" | "calendar" = rawView === "calendar" ? "calendar" : "month";
  // Plan mode: amounts become inputs next to typical spend.
  const [rawEdit, setEdit] = useHashParam("edit", { replace: true });
  const editing = rawEdit === "1";
  const [applyMode, setApplyMode] = useState<BudgetLineMode>("ongoing");

  const { data, isLoading, error, isPlaceholderData, refetch } = useQuery({
    ...queries.budget(month),
    placeholderData: keepPreviousData,
  });
  const { data: suggestions } = useQuery({ ...queries.budgetSuggestions(month), enabled: editing });
  const { data: categories = [] } = useQuery({ ...queries.categories(), enabled: editing });

  const refresh = () => invalidate(qc, keys.budget);

  const setLine = useMutation({
    mutationFn: ({ category_id, change }: { category_id: string; change: LineChange }) =>
      mutations.setBudgetLine({
        month,
        category_id,
        ...change,
        // "This month only" is about amounts; period and rollover changes
        // always apply from now on.
        mode: change.planned != null && change.period == null ? applyMode : "ongoing",
      }),
    onSuccess: refresh,
  });
  const stopLine = useMutation({
    mutationFn: (line: BudgetLine) => mutations.stopBudgetLine({ month, category_id: line.category_id }),
    onSuccess: refresh,
  });
  const setPeriod = useMutation({
    mutationFn: (body: { income_planned?: number | null; other_planned?: number | null }) =>
      mutations.setBudgetPeriod({ month, ...body }),
    onSuccess: refresh,
  });
  const autofill = useMutation({
    mutationFn: () => mutations.budgetAutofill({ month }),
    onSuccess: (res) => {
      toast.success(
        res.filled === 0
          ? "Nothing to add — your biggest categories are already budgeted"
          : `Added ${res.filled} ${res.filled === 1 ? "category" : "categories"} at their typical amounts — adjust anything below`,
      );
      refresh();
      setEdit("1");
    },
  });

  const allLines = useMemo(() => (data ? [...data.lines, ...data.yearly.lines] : []), [data]);
  const drawerLine = drawerCategoryId ? (allLines.find((l) => l.category_id === drawerCategoryId) ?? null) : null;

  const monthNav = (
    <div className="flex items-center gap-1">
      <Button
        variant="ghost"
        size="icon-sm"
        onClick={() => setMonth(shiftMonth(month, -1))}
        aria-label="Previous month"
        className="text-muted-foreground hover:text-foreground"
      >
        <ChevronLeft size={16} />
      </Button>
      <span className="min-w-[7.5rem] text-center text-sm font-medium tabular-nums">{monthLabel(month)}</span>
      <Button
        variant="ghost"
        size="icon-sm"
        onClick={() => setMonth(shiftMonth(month, 1))}
        aria-label="Next month"
        className="text-muted-foreground hover:text-foreground"
      >
        <ChevronRight size={16} />
      </Button>
    </div>
  );

  const showEditToggle = view === "month" && data != null && (editing || hasPlan(data));

  const header = (
    <PageHeader title="Budget" level={1} sticky>
      <SegmentedToggle
        label="Budget view"
        options={[{ value: "month", label: "Month" }, { value: "calendar", label: "Year" }]}
        value={view}
        onChange={(v) => setView(v === "month" ? null : v)}
      />
      {view === "month" && monthNav}
      {showEditToggle && (
        editing ? (
          <Button size="sm" onClick={() => setEdit(null)}>Done</Button>
        ) : (
          <Button size="sm" variant="outline" onClick={() => setEdit("1")}>
            <Pencil size={13} />
            Edit budget
          </Button>
        )
      )}
    </PageHeader>
  );

  if (view === "calendar") {
    return (
      <div className="flex flex-col">
        {header}
        <div className="p-6 pb-16">
          <BudgetCalendarView onSelectMonth={(m) => { setMonth(m); setView(null); }} />
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="flex flex-col">
        {header}
        <div className="space-y-4 p-6">
          <Skeleton className="h-28 rounded-xl" />
          <Skeleton className="h-64 rounded-xl" />
        </div>
      </div>
    );
  }
  if (error || !data) {
    return (
      <div className="flex flex-col">
        {header}
        <ErrorState title="Failed to load budget" onRetry={() => refetch()} />
      </div>
    );
  }

  let content;
  if (editing) {
    content = (
      <BudgetPlanEditor
        data={data}
        suggestions={suggestions}
        categories={categories}
        applyMode={applyMode}
        onApplyModeChange={setApplyMode}
        onSetLine={(category_id, change) => setLine.mutate({ category_id, change })}
        onStopLine={(line) => stopLine.mutate(line)}
        onSetPeriod={(body) => setPeriod.mutate(body)}
      />
    );
  } else if (!hasPlan(data)) {
    content = (
      <BudgetEmptyState
        onAutofill={() => autofill.mutate()}
        onManual={() => setEdit("1")}
        pending={autofill.isPending}
      />
    );
  } else {
    content = (
      <>
        <BudgetSummary data={data} />
        <BudgetList
          data={data}
          onSelectLine={(line) => setDrawerCategoryId(line.category_id)}
          onOpenEverythingElse={() => navigate(transactionsHref({ month }))}
          onEdit={() => setEdit("1")}
        />
      </>
    );
  }

  return (
    <div className="flex flex-col">
      {header}
      <div className={cn("space-y-4 p-6 pb-16", isPlaceholderData && "opacity-50 transition-opacity")}>
        {content}
      </div>

      <BudgetLineDrawer
        line={drawerLine}
        month={month}
        paceElapsed={data.pace.current ? data.pace.percent_elapsed : null}
        onClose={() => setDrawerCategoryId(null)}
        onSetRollover={(line, rollover) =>
          setLine.mutate({ category_id: line.category_id, change: { rollover } })}
      />
    </div>
  );
}

function BudgetEmptyState({ onAutofill, onManual, pending }: {
  onAutofill: () => void;
  onManual: () => void;
  pending: boolean;
}) {
  return (
    <div className="rounded-xl border border-dashed bg-card">
      <EmptyState
        className="py-16"
        title="Set up your budget"
        description="Pick the few categories you want to keep an eye on, and give everything else one catch-all amount. Budgets carry forward each month until you change them."
        action={
          <div className="flex flex-wrap items-center justify-center gap-2">
            <Button disabled={pending} onClick={onAutofill}>
              <Sparkles size={15} />
              Suggest a starting budget
            </Button>
            <Button variant="outline" onClick={onManual}>
              Start from scratch
            </Button>
          </div>
        }
      />
    </div>
  );
}
