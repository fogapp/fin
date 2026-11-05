import { useState } from "react";
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { queries } from "@/api/queries";
import { mutations } from "@/api/mutations";
import { invalidate, keys } from "@/api/keys";
import { ErrorState } from "@/components/PageState";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { cn, formatCurrency } from "@/lib/utils";
import { currentMonth, formatMonthShort } from "./budgetMonth";
import type { BudgetCalendarCell, BudgetCalendarRow } from "@/api/types";
import { AmountInput } from "./AmountInput";

// Year-at-a-glance grid: one row per budgeted category, one column per month,
// each cell showing actual over planned. Past and current months carry both
// numbers; future months only the plan. Red = over that month's budget.
// Clicking a monthly row's amount in this or a later month sets a one-month
// amount for it — planning ahead for a bigger December, say — and clearing it
// falls back to the ongoing budget.
export function BudgetCalendarView({ onSelectMonth }: {
  /** Jump the month view to the clicked column. */
  onSelectMonth: (month: string) => void;
}) {
  const qc = useQueryClient();
  const [year, setYear] = useState(() => new Date().getFullYear());
  const [editing, setEditing] = useState<{ categoryId: string; month: string } | null>(null);
  const { data, isLoading, error, refetch, isPlaceholderData } = useQuery({
    ...queries.budgetCalendar(year),
    placeholderData: keepPreviousData,
  });
  const setMonthAmount = useMutation({
    mutationFn: async ({ categoryId, month, planned }: { categoryId: string; month: string; planned: number | null }) => {
      if (planned == null) await mutations.stopBudgetLine({ month, category_id: categoryId, month_only: true });
      else await mutations.setBudgetLine({ month, category_id: categoryId, planned, mode: "month_only" });
    },
    onSuccess: () => invalidate(qc, keys.budget),
  });

  if (isLoading) return <Skeleton className="h-96 rounded-xl" />;
  if (error || !data) return <ErrorState title="Failed to load the budget calendar" onRetry={() => refetch()} />;

  const thisMonth = currentMonth();
  const groups = [
    { key: "monthly", label: "Monthly", rows: data.rows.filter((r) => r.period === "monthly") },
    { key: "yearly", label: "Yearly", rows: data.rows.filter((r) => r.period === "yearly") },
  ].filter(({ rows }) => rows.length > 0);

  return (
    <div className={cn("rounded-xl border bg-card", isPlaceholderData && "opacity-50 transition-opacity")}>
      <div className="flex items-center justify-between gap-3 border-b px-4 py-2">
        <div>
          <p className="text-sm font-medium">{year}</p>
          <p className="text-xs text-muted-foreground">Click this or a later month's amount to set a one-month budget for it.</p>
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            aria-label="Previous year"
            onClick={() => setYear((y) => y - 1)}
            className="flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
          >
            <ChevronLeft size={14} />
          </button>
          <button
            type="button"
            aria-label="Next year"
            onClick={() => setYear((y) => y + 1)}
            className="flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
          >
            <ChevronRight size={14} />
          </button>
        </div>
      </div>

      {data.rows.length === 0 ? (
        <EmptyState
          title="Nothing budgeted this year"
          description="Set category budgets on the month view and they'll appear here."
          className="py-16"
        />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b">
                <th className="sticky left-0 z-10 bg-card px-4 py-2 text-left font-medium text-muted-foreground">Category</th>
                {data.months.map((m) => (
                  <th
                    key={m}
                    className={cn("px-2 py-2 text-right font-medium text-muted-foreground", m === thisMonth && "bg-primary/5 text-primary")}
                  >
                    <button
                      type="button"
                      onClick={() => onSelectMonth(m)}
                      className="rounded px-1 tabular-nums hover:bg-accent focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary"
                      title={`Open ${formatMonthShort(m)} in the month view`}
                    >
                      {formatMonthShort(m)}
                    </button>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {groups.map(({ key, label, rows }) => (
                <CalendarGroup
                  key={key}
                  label={label}
                  rows={rows}
                  months={data.months}
                  thisMonth={thisMonth}
                  editing={editing}
                  onEdit={setEditing}
                  onSetAmount={(categoryId, month, planned) => {
                    setEditing(null);
                    setMonthAmount.mutate({ categoryId, month, planned });
                  }}
                />
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2">
                <td className="sticky left-0 z-10 bg-card px-4 py-2 font-semibold">Total</td>
                {data.months.map((m) => (
                  <CalendarCell key={m} cell={data.totals[m]} month={m} thisMonth={thisMonth} emphasize />
                ))}
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  );
}

function CalendarGroup({ label, rows, months, thisMonth, editing, onEdit, onSetAmount }: {
  label: string;
  rows: BudgetCalendarRow[];
  months: string[];
  thisMonth: string;
  editing: { categoryId: string; month: string } | null;
  onEdit: (cell: { categoryId: string; month: string } | null) => void;
  onSetAmount: (categoryId: string, month: string, planned: number | null) => void;
}) {
  return (
    <>
      <tr className="border-b bg-muted/30">
        <td colSpan={months.length + 1} className="sticky left-0 px-4 py-1 text-tiny font-semibold uppercase tracking-wide text-muted-foreground">
          {label}
        </td>
      </tr>
      {rows.map((row) => (
        <tr key={row.category_id} className="border-b last:border-b-0">
          <td className="sticky left-0 z-10 max-w-40 truncate bg-card px-4 py-1.5 font-medium" title={row.category_name}>
            {row.category_name}
            {row.annual != null && (
              <span className="block text-tiny font-normal text-muted-foreground">{formatCurrency(row.annual, true)}/yr</span>
            )}
          </td>
          {months.map((m) => {
            const isEditing = editing?.categoryId === row.category_id && editing.month === m;
            return isEditing ? (
              <td key={m} className="px-1 py-1">
                <AmountInput
                  autoFocus
                  allowEmpty
                  value={row.months[m]?.override ? row.months[m]?.planned ?? null : null}
                  placeholder={row.months[m]?.planned != null ? String(row.months[m]?.planned) : ""}
                  label={`${row.category_name} budget for ${formatMonthShort(m)}`}
                  onCommit={(v) => onSetAmount(row.category_id, m, v)}
                  className="w-24"
                />
              </td>
            ) : (
              <CalendarCell
                key={m}
                cell={row.months[m]}
                month={m}
                thisMonth={thisMonth}
                onEdit={row.period === "monthly" && m >= thisMonth
                  ? () => onEdit({ categoryId: row.category_id, month: m })
                  : undefined}
              />
            );
          })}
        </tr>
      ))}
    </>
  );
}

function CalendarCell({ cell, month, thisMonth, emphasize = false, onEdit }: {
  cell: BudgetCalendarCell | undefined;
  month: string;
  thisMonth: string;
  emphasize?: boolean;
  /** Makes the planned amount a button that opens an inline editor. */
  onEdit?: () => void;
}) {
  const isFuture = month > thisMonth;
  const planned = cell?.planned ?? null;
  const actual = cell?.actual ?? 0;
  const over = planned != null && planned > 0 && actual > planned;
  const override = cell?.override ?? false;
  const plannedLabel = planned != null ? formatCurrency(planned, true) : "—";
  const plannedNode = onEdit ? (
    <button
      type="button"
      onClick={onEdit}
      className={cn(
        "rounded px-0.5 hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary",
        override && "font-medium text-primary",
      )}
      title={override ? "One-month amount — click to change or clear" : "Set a one-month amount"}
    >
      {plannedLabel}
    </button>
  ) : plannedLabel;

  return (
    <td className={cn("px-2 py-1.5 text-right tabular-nums", month === thisMonth && "bg-primary/5")}>
      {isFuture ? (
        <span className="text-muted-foreground">{plannedNode}</span>
      ) : (
        <span className="inline-flex flex-col items-end leading-tight">
          <span className={cn(over && "text-negative", emphasize && "font-semibold")}>
            {formatCurrency(actual, true)}
          </span>
          <span className="text-tiny text-muted-foreground">
            {planned != null || onEdit ? <>of {plannedNode}</> : "unplanned"}
          </span>
        </span>
      )}
    </td>
  );
}
